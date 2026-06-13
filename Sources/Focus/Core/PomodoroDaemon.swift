import Foundation
import Darwin

enum PomodoroDaemon {
    /// Launch a new pomodoro. Writes state, forks a detached `_pomodoro-run` child,
    /// backfills the PID into the state file, and returns. Recovers from a stale
    /// state file (dead PID) by clearing and proceeding.
    static func launch(goal: String, workMinutes: Int, breakMinutes: Int, music: String?, block: Bool) throws {
        let session = PomodoroSession.default
        if let existing = session.current {
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
        let (workEnd, breakEnd) = session.deadlines(
            workMinutes: workMinutes, breakMinutes: breakMinutes, at: now
        )
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
        let handle = try Shell.spawn(Shell.Command(Paths.selfExecutable, args))

        let active = PomodoroSession.Active(
            goal: goal, pid: handle.pid, startedAt: now,
            workEnd: workEnd, breakEnd: breakEnd, music: musicURI, block: block
        )
        try session.save(active)

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
    ///   break it asks PomodoroSession for the next iteration, rewrites the state
    ///   file, and starts a fresh work phase with the same goal. Block + music
    ///   carry over so we don't re-spawn sudo or restart playback. The setting is
    ///   re-read each iteration, so flipping it off mid-session takes effect at
    ///   the next break.
    static func runDaemon(
        goal: String, workEnd: Double, breakEnd: Double,
        workMinutes: Int, breakMinutes: Int,
        music: String?, block: Bool
    ) {
        signal(SIGHUP, SIG_IGN)
        _ = Darwin.setsid()

        if block {
            let blocked = Shell.run(Shell.Command(
                Paths.selfExecutable,
                ["block"] + Defaults.dohSuppressionFlags,
                sudo: true
            )).status == 0
            // The UI can't surface a daemon-side sudo failure, so warn here. This
            // is the daemon's only console side effect (everything else flows
            // through the state file, which AppState reads).
            if !blocked {
                FileHandle.standardError.write(Data(
                    "focus: warning — sudo -n block failed. Is /etc/sudoers.d/focus installed?\n".utf8
                ))
            }
        }

        if let music = music, !music.isEmpty {
            Shell.run(Shell.Command(Paths.selfExecutable, ["music", music]))
        }

        let session = PomodoroSession.default
        var currentWorkEnd = workEnd
        var currentBreakEnd = breakEnd

        while true {
            sleepUntil(currentWorkEnd)
            sleepUntil(currentBreakEnd)

            if !Defaults.autoStartNextSession { break }

            // Loop: roll deadlines and persist new state. The menu bar app
            // notices the workEnd change and emits the "Starting next session"
            // notification on its next refresh.
            //
            // If the state file vanished mid-loop (e.g. `pomodoro stop` raced
            // with the break→work transition), bail out instead of writing a
            // phantom next session. Pre-refactor code rolled deadlines
            // unconditionally and only skipped the save; the new behavior
            // matches stop's intent of ending the daemon cleanly.
            if let prev = session.current {
                let next = session.nextSession(
                    after: prev,
                    workMinutes: workMinutes, breakMinutes: breakMinutes
                )
                try? session.save(next)
                currentWorkEnd = next.workEnd
                currentBreakEnd = next.breakEnd
            } else {
                break
            }
        }

        clearEverything(unblock: block)
    }

    static func stop() {
        let session = PomodoroSession.default
        guard let state = session.current else {
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
            Shell.run(Shell.Command(Paths.selfExecutable, ["unblock"], sudo: true))
        }
        // Music doesn't need root; call Core directly instead of forking the CLI.
        LocalPlayback.stop()
        PomodoroSession.default.clear()
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

    // No "focus:" prefix — ArgumentParser frames thrown errors as "Error: …",
    // and a doubled "Error: focus: …" reads badly.
    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "a pomodoro is already running. Stop it first."
        case .notRoot:
            return "this command needs sudo (it writes /etc/hosts)"
        case .emptyBlockList(let url):
            return "\(url.path) is empty"
        case .missingFile(let url):
            return "file not found: \(url.path)"
        case .missingMusicSource:
            return "no music source. Pass a preset name, --uri, --file, or set FOCUS_MUSIC_URI. See `focus music --list`."
        }
    }
}
