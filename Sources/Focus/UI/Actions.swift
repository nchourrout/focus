import Foundation
import AppKit
/// Thin dispatch layer: every menu action spawns the focus CLI (same binary,
/// different argv) and returns immediately. All state changes flow back
/// through the state file, which AppState picks up on its next tick.
@MainActor
enum Actions {
    // MARK: Pomodoro

    static func promptAndStartPomodoro() {
        let alert = NSAlert()
        alert.messageText = "Start pomodoro"
        alert.informativeText = "What are you working on?"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "goal"
        alert.accessoryView = field
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let goal = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !goal.isEmpty {
                startPomodoro(goal: goal)
            }
        }
    }

    /// Start a session with the user's settings. No flags: the CLI reads the same
    /// settings we would (see `PomodoroPlan`), so passing them here would just be
    /// a second place for the rules to drift.
    static func startPomodoro(goal: String) {
        spawn(["pomodoro", "start", goal])
    }

    static func stopPomodoro() {
        spawn(["pomodoro", "stop"])
    }

    /// Freeze the running session; the block lifts and music stops until resume.
    static func pausePomodoro() {
        spawn(["pomodoro", "pause"])
    }

    /// Continue a paused session where it left off.
    static func resumePomodoro() {
        spawn(["pomodoro", "resume"])
    }

    /// End the running break early; the next work phase starts immediately.
    /// No-op with a friendly message unless a session is resting in a break —
    /// the CLI owns those guards, so the menu item can fire freely.
    static func skipBreak() {
        spawn(["pomodoro", "skip-break"])
    }

    /// Single-shortcut affordance: stop if a session is running, resume if one
    /// is paused, otherwise prompt for a goal and start.
    static func togglePomodoro() {
        // One read: two would let the daemon write between them and route a
        // record that no longer exists to stopPomodoro.
        guard let current = PomodoroSession.default.current else {
            promptAndStartPomodoro()
            return
        }
        if current.pausedAt != nil { resumePomodoro() } else { stopPomodoro() }
    }

    // MARK: Block

    /// Toggle the website block and post a system notification with the new
    /// state so the click has visible effect (the menu bar icon also changes,
    /// but only after AppState's next 1Hz refresh).
    static func toggleBlock() {
        let command = Shell.Command(
            Paths.selfExecutable,
            ["toggle", "--json"] + Defaults.dohSuppressionFlags,
            sudo: true,
            captureStdout: true
        )
        do {
            let handle = try Shell.spawn(command)
            handle.onExit { status, stdout in
                if status != 0 {
                    Task { @MainActor in showSudoersMissingAlert() }
                    return
                }
                // Decode the documented payload rather than substring-matching
                // it. On the (bug-shaped) failure path, skip the banner: the
                // AppState tick reflects the real /etc/hosts state within 1s.
                let active: Bool
                do {
                    active = try JSONDecoder()
                        .decode(BlockStatus.self, from: Data(stdout.utf8)).active
                } catch {
                    Log.actions.error(
                        "toggle --json output didn't decode as BlockStatus: \(stdout, privacy: .public)"
                    )
                    return
                }
                Task { @MainActor in
                    LocalNotifications.post(
                        title: active ? "Websites blocked" : "Websites unblocked",
                        body: active
                            ? "Distraction list is active."
                            : "Distractions are reachable again."
                    )
                }
            }
        } catch {
            Log.actions.error("toggle failed to launch: \(error.localizedDescription, privacy: .public)")
            showSudoersMissingAlert()
        }
    }

    /// Re-run `block` to pick up changed settings without flipping state. No-op
    /// if the block isn't active. Idempotent: activate rewrites the marker
    /// section in place.
    static func reapplyBlock() {
        guard SiteBlock.default.isActive else { return }
        spawnSudo(["block"] + Defaults.dohSuppressionFlags)
    }

    // MARK: Music

    /// Music actions don't need root, so we call Core directly instead of forking
    /// a CLI subprocess — saves a fork and lets us surface errors to the user.
    ///
    /// `playIfNeeded` because the music menu is a radio group: the playing
    /// station carries a checkmark, and clicking the one already checked used to
    /// fade it out and reconnect to the same stream.
    static func playMusic(_ station: Station) {
        do {
            try LocalPlayback.playIfNeeded(station)
        } catch {
            Log.actions.error("playMusic \(station.label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func stopMusic() {
        LocalPlayback.stop()
    }

    /// Apply a music change while audio is already playing: switch the stream, or
    /// stop if the user picked "None". No-op when nothing is playing — the new
    /// station takes effect at the next pomodoro start.
    static func reapplyMusic(_ station: Station?) {
        guard LocalPlayback.isPlaying else { return }
        if let station {
            playMusic(station)
        } else {
            stopMusic()
        }
    }

    // MARK: Private

    /// Fire-and-forget invocation of the focus binary. Launch errors are routed to
    /// Unified Logging instead of popping an alert for every missed click — check
    /// Console.app filtered on subsystem `com.nchourrout.focus` when debugging.
    private static func spawn(_ args: [String]) {
        do {
            try Shell.spawn(Shell.Command(Paths.selfExecutable, args))
        } catch {
            Log.actions.error("spawn \(args.first ?? "?", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Same as `spawn` but routes through `sudo -n`. Requires the sudoers drop-in.
    /// Uses `onExit` (event-driven, no thread parking) to detect sudo failures and
    /// surface an alert, so the user understands why the action appeared to
    /// do nothing. Shared with `AppState`'s dead-daemon recovery, which unblocks
    /// on the user's behalf after cleaning up a crashed session.
    static func spawnSudo(_ args: [String]) {
        do {
            let handle = try Shell.spawn(Shell.Command(Paths.selfExecutable, args, sudo: true))
            handle.onExit { status, _ in
                guard status != 0 else { return }
                Task { @MainActor in showSudoersMissingAlert() }
            }
        } catch {
            Log.actions.error("sudo spawn \(args.first ?? "?", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            showSudoersMissingAlert()
        }
    }

    private static func showSudoersMissingAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Focus needs permission to edit /etc/hosts"
        alert.informativeText = "Grant permission once and Focus will be able to block and unblock sites without any further prompts."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Grant Permission…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        SudoersInstaller.installWithUI(
            onSuccess: {
                let ok = NSAlert()
                ok.messageText = "Permission granted"
                ok.informativeText = "Try the action again."
                ok.runModal()
            },
            onError: { error in
                NSAlert(error: error).runModal()
            }
        )
    }
}
