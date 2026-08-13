import Foundation
import Darwin

/// Process-level lifecycle for a pomodoro: fork the detached daemon, hand it a
/// plan, and stop it again. The loop the daemon actually runs lives in
/// `SessionRunner`.
enum PomodoroDaemon {
    /// Launch a new pomodoro. Writes state, forks a detached `_pomodoro-run` child,
    /// and returns. Recovers from a stale state file (dead PID) by clearing and
    /// proceeding.
    static func launch(_ plan: PomodoroPlan) throws {
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
            SessionRunner.endSession(unblock: existing.block, clearing: session,
                                     effects: LiveSessionEffects())
        }

        let now = Date().timeIntervalSince1970
        let first = session.firstSession(
            plan: plan, cadence: .fromSettings, pid: 0, at: now
        )

        // Spawn the daemon first so we can write the state file once, with the real PID.
        // Writing a placeholder state beforehand opened a window where `pomodoro stop`
        // could see pid=0, skip the signal, and leak the daemon.
        var args = [
            "_pomodoro-run",
            "--goal", plan.goal,
            "--work-end", String(first.workEnd),
            "--break-end", String(first.breakEnd),
            "--work-minutes", String(plan.workMinutes),
            "--break-minutes", String(plan.breakMinutes),
        ]
        if let station = plan.station {
            args.append(contentsOf: ["--music", station.uri])
        }
        if !plan.block { args.append("--no-block") }
        let handle = try Shell.spawn(Shell.Command(Paths.selfExecutable, args))

        var active = first
        active.pid = handle.pid
        try session.save(active)

        print("focus: pomodoro started — \(plan.workMinutes)min work, \(plan.breakMinutes)min break — \(plan.goal)")
    }

    /// Body of the hidden `_pomodoro-run` subcommand. Runs in the detached child
    /// process, then hands off to `SessionRunner` for the loop itself.
    ///
    /// - We ignore SIGHUP and setsid() ourselves so we survive the parent shell exiting.
    /// - We do NOT install a SIGTERM handler. Default behavior is to terminate, which
    ///   means cleanup on interruption is the responsibility of `stop()`'s fallback
    ///   path. Normal completion cleans up inside the runner.
    static func runDaemon(_ plan: PomodoroPlan, workEnd: Double, breakEnd: Double) {
        signal(SIGHUP, SIG_IGN)
        _ = Darwin.setsid()

        // First line of the run: from here on the log is the only way to see what
        // this process did, since its stdio is /dev/null.
        Log.daemon.notice(
            """
            starting \(plan.workMinutes, privacy: .public)/\(plan.breakMinutes, privacy: .public) \
            block=\(plan.block, privacy: .public) \
            music=\(plan.station?.label ?? "none", privacy: .public)
            """
        )

        SessionRunner(
            plan: plan,
            session: .default,
            effects: LiveSessionEffects()
        ).run(workEnd: workEnd, breakEnd: breakEnd)
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
        SessionRunner.endSession(unblock: state.block, clearing: session,
                                 effects: LiveSessionEffects())
        print("focus: pomodoro stopped")
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
