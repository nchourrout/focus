import Foundation
import Darwin

enum PomodoroDaemon {
    /// Launch a new pomodoro. Writes state, forks a detached `_pomodoro-run` child,
    /// backfills the PID into the state file, and returns. Recovers from a stale
    /// state file (dead PID) by clearing and proceeding.
    static func launch(goal: String, workMinutes: Int, breakMinutes: Int, music: String?, block: Bool) throws {
        if let existing = PomodoroState.current {
            // Verify the PID is both alive *and* actually our daemon, to guard against
            // PID recycling (a long-running process reusing the dead daemon's PID).
            if isOurProcess(pid: existing.pid, expectedStart: existing.startedAt) {
                throw CLIError.alreadyRunning
            }
            print("focus: clearing stale pomodoro state from previous session")
            // Use the prior session's block flag — if it was running with --no-block,
            // there's nothing to unblock.
            clearEverything(unblock: existing.block)
        }

        let now = Date().timeIntervalSince1970
        let workEnd = now + Double(workMinutes * 60)
        let breakEnd = workEnd + Double(breakMinutes * 60)
        // Single source of truth for preset / env-var resolution. Fails fast on unknown preset.
        let musicURI = try MusicPresets.resolve(target: music, explicitURI: nil)

        // Spawn the daemon first so we can write the state file once, with the real PID.
        // Writing a placeholder state beforehand opened a window where `pomodoro stop`
        // could see pid=0, skip the signal, and leak the daemon.
        var args = [
            "_pomodoro-run",
            "--goal", goal,
            "--work-end", String(workEnd),
            "--break-end", String(breakEnd),
            "--work-minutes", String(workMinutes),
            "--break-minutes", String(breakMinutes),
        ]
        if let music = musicURI {
            args.append(contentsOf: ["--music", music])
        }
        if !block { args.append("--no-block") }
        let p = try Subprocess.launchSilent(Paths.selfExecutable, args)

        let state = PomodoroState(
            goal: goal, pid: p.processIdentifier, startedAt: now,
            workEnd: workEnd, breakEnd: breakEnd, music: musicURI, block: block
        )
        try state.save()

        print("focus: pomodoro started — \(workMinutes)min work, \(breakMinutes)min break — \(goal)")
    }

    /// Body of the hidden `_pomodoro-run` subcommand. Runs in the detached child process.
    ///
    /// Design notes:
    /// - We ignore SIGHUP and setsid() ourselves so we survive the parent shell exiting.
    /// - We do NOT install a SIGTERM handler. Default behavior is to terminate, which
    ///   means cleanup on interruption is the responsibility of `pomodoro stop`'s fallback
    ///   path. Normal completion cleans up explicitly at the end of this function.
    /// - When `Defaults.autoStartNextSession` is on, the daemon loops: after the
    ///   break it computes new deadlines, rewrites the state file, and starts a
    ///   fresh work phase with the same goal. Block + music carry over so we
    ///   don't re-spawn sudo or restart playback. The setting is re-read each
    ///   iteration, so flipping it off mid-session takes effect at the next break.
    static func runDaemon(
        goal: String, workEnd: Double, breakEnd: Double,
        workMinutes: Int, breakMinutes: Int,
        music: String?, block: Bool
    ) {
        signal(SIGHUP, SIG_IGN)
        _ = Darwin.setsid()

        var blockFailed = false
        if block {
            let blockArgs = ["-n", Paths.selfExecutable.path, "block"]
                + Defaults.dohSuppressionFlags
            let blocked = Subprocess.run("/usr/bin/sudo", blockArgs) == 0
            if !blocked {
                blockFailed = true
                FileHandle.standardError.write(Data(
                    "focus: warning — sudo -n block failed. Is /etc/sudoers.d/focus installed?\n".utf8
                ))
            }
        }

        if let music = music, !music.isEmpty {
            _ = Subprocess.run(Paths.selfExecutable.path, ["music", music])
        }

        // Notifications are emitted by AppState in the menu bar app process so
        // the Focus icon shows on the banner. The daemon doesn't post — its
        // only side effect here is the state file (and the block warning below
        // when sudo -n fails, since the UI can't surface that condition).
        if blockFailed {
            FileHandle.standardError.write(Data(
                "focus: warning — sudo -n block failed. Run install-sudoers.\n".utf8
            ))
        }

        var currentWorkEnd = workEnd
        var currentBreakEnd = breakEnd

        while true {
            sleepUntil(currentWorkEnd)
            sleepUntil(currentBreakEnd)

            if !Defaults.autoStartNextSession { break }

            // Loop: roll deadlines and persist new state. The menu bar app
            // notices the workEnd change and emits the "Starting next session"
            // notification on its next refresh.
            let now = Date().timeIntervalSince1970
            currentWorkEnd = now + Double(workMinutes * 60)
            currentBreakEnd = currentWorkEnd + Double(breakMinutes * 60)

            if let prev = PomodoroState.current {
                let next = PomodoroState(
                    goal: prev.goal, pid: prev.pid, startedAt: now,
                    workEnd: currentWorkEnd, breakEnd: currentBreakEnd,
                    music: prev.music, block: prev.block
                )
                try? next.save()
            }
        }

        clearEverything(unblock: block)
    }

    static func stop() {
        guard let state = PomodoroState.current else {
            print("focus: no pomodoro running")
            return
        }
        // Only signal if the PID is still ours; skip if the PID has been recycled.
        // The `pid > 0` check is a defensive belt: `kill(0, SIGTERM)` would signal
        // every process in our process group.
        if state.pid > 0, isOurProcess(pid: state.pid, expectedStart: state.startedAt) {
            _ = kill(state.pid, SIGTERM)
            for _ in 0..<10 {
                usleep(100_000)
                if !isPIDAlive(state.pid) { break }
            }
        }
        // Daemon doesn't clean up on SIGTERM (no handler), so do it here.
        // Only unblock if the session asked us to block in the first place — sparing
        // a sudo -n call (and the matching sudoers prompt if it weren't installed).
        clearEverything(unblock: state.block)
        print("focus: pomodoro stopped")
    }

    private static func clearEverything(unblock: Bool) {
        if unblock {
            _ = Subprocess.run("/usr/bin/sudo", ["-n", Paths.selfExecutable.path, "unblock"])
        }
        // Music doesn't need root; call Core directly instead of forking the CLI.
        LocalPlayback.stop()
        PomodoroState.clearFile()
    }

    private static func sleepUntil(_ deadline: TimeInterval) {
        let remaining = deadline - Date().timeIntervalSince1970
        if remaining > 0 {
            Thread.sleep(forTimeInterval: remaining)
        }
    }
}

enum CLIError: Error, LocalizedError {
    case alreadyRunning
    case notRoot
    case emptyBlockList(URL)
    case missingFile(URL)
    case missingMusicSource

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "focus: a pomodoro is already running. Stop it first."
        case .notRoot:
            return "focus: this command needs sudo (it writes /etc/hosts)"
        case .emptyBlockList(let url):
            return "focus: \(url.path) is empty"
        case .missingFile(let url):
            return "focus: file not found: \(url.path)"
        case .missingMusicSource:
            return "focus: no music source. Pass a preset name, --uri, --file, or set FOCUS_MUSIC_URI. See `focus music --list`."
        }
    }
}
