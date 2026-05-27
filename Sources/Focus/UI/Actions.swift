import Foundation
import AppKit
import os

private let log = Logger(subsystem: "com.nchourrout.focus", category: "actions")

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
                startPomodoro(goal: goal, music: nil)
            }
        }
    }

    static func startPomodoro(goal: String, music: String?) {
        var args = [
            "pomodoro", "start", goal,
            "--work", String(Defaults.workMinutes),
            "--break", String(Defaults.breakMinutes),
        ]
        if !Defaults.blockDuringPomodoro {
            args.append("--no-block")
        }
        if let music = music, !music.isEmpty {
            args.append(contentsOf: ["--music", music])
        }
        spawn(args)
    }

    static func stopPomodoro() {
        spawn(["pomodoro", "stop"])
    }

    /// Single-shortcut affordance: stop if a session is running, otherwise prompt
    /// for a goal and start one.
    static func togglePomodoro() {
        if PomodoroSession.default.current != nil {
            stopPomodoro()
        } else {
            promptAndStartPomodoro()
        }
    }

    // MARK: Block

    /// Toggle the website block and post a system notification with the new
    /// state so the click has visible effect (the menu bar icon also changes,
    /// but only after AppState's next 1Hz refresh).
    static func toggleBlock() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", Paths.selfExecutable.path, "toggle", "--json"]
            + Defaults.dohSuppressionFlags
        p.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                Task { @MainActor in showSudoersMissingAlert() }
                return
            }
            let stdout = String(
                data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let active = stdout.contains("\"active\": true")
            Task { @MainActor in
                LocalNotifications.post(
                    title: active ? "Websites blocked" : "Websites unblocked",
                    body: active
                        ? "Distraction list is active."
                        : "Distractions are reachable again."
                )
            }
        }
        do {
            try p.run()
        } catch {
            log.error("toggle failed to launch: \(error.localizedDescription, privacy: .public)")
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
    static func playMusic(_ preset: String) {
        do {
            try LocalPlayback.play(target: preset)
        } catch {
            log.error("playMusic \(preset, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func stopMusic() {
        LocalPlayback.stop()
    }

    // MARK: Private

    /// Fire-and-forget invocation of the focus binary. Launch errors are routed to
    /// Unified Logging instead of popping an alert for every missed click — check
    /// Console.app filtered on subsystem `com.nchourrout.focus` when debugging.
    private static func spawn(_ args: [String]) {
        do {
            _ = try Subprocess.launchSilent(Paths.selfExecutable, args)
        } catch {
            log.error("spawn \(args.first ?? "?", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Same as `spawn` but routes through `sudo -n`. Requires the sudoers drop-in.
    /// Uses `terminationHandler` (event-driven, no thread parking) to detect sudo
    /// failures and surface an alert, so the user understands why the menu action
    /// appeared to do nothing.
    private static func spawnSudo(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", Paths.selfExecutable.path] + args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { proc in
            guard proc.terminationStatus != 0 else { return }
            Task { @MainActor in showSudoersMissingAlert() }
        }
        do {
            try p.run()
        } catch {
            log.error("sudo spawn \(args.first ?? "?", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
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
