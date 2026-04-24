import Foundation
import Darwin

enum PomodoroDaemon {
    /// Launch a new pomodoro. Writes state, forks a detached `_pomodoro-run` child,
    /// backfills the PID into the state file, and returns. Recovers from a stale
    /// state file (dead PID) by clearing and proceeding.
    static func launch(goal: String, workMinutes: Int, breakMinutes: Int, music: String?) throws {
        if let existing = PomodoroState.current {
            if isPIDAlive(existing.pid) {
                throw CLIError.alreadyRunning
            }
            print("focus: clearing stale pomodoro state from previous session")
            clearEverything()
        }

        let now = Date().timeIntervalSince1970
        let workEnd = now + Double(workMinutes * 60)
        let breakEnd = workEnd + Double(breakMinutes * 60)
        let musicValue = (music?.isEmpty == false ? music : ProcessInfo.processInfo.environment["FOCUS_SPOTIFY_URI"]) ?? ""

        // Write state before forking so `pomodoro stop` always sees the session.
        var state = PomodoroState(
            goal: goal, pid: 0, startedAt: now,
            workEnd: workEnd, breakEnd: breakEnd, music: musicValue
        )
        try state.save()

        let p = Process()
        p.executableURL = Paths.selfExecutable
        var args = [
            "_pomodoro-run",
            "--goal", goal,
            "--work-end", String(workEnd),
            "--break-end", String(breakEnd),
        ]
        if !musicValue.isEmpty {
            args.append(contentsOf: ["--music", musicValue])
        }
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()

        state.pid = p.processIdentifier
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
    static func runDaemon(goal: String, workEnd: Double, breakEnd: Double, music: String?) {
        signal(SIGHUP, SIG_IGN)
        _ = Darwin.setsid()

        let blocked = Subprocess.run("/usr/bin/sudo", ["-n", Paths.selfExecutable.path, "block"]) == 0

        if let music = music, !music.isEmpty {
            _ = Subprocess.run(Paths.selfExecutable.path, ["music", music])
        }

        Notifier.post(
            title: "Pomodoro started",
            body: goal + (blocked ? "" : "\n(couldn't block websites)")
        )

        sleepUntil(workEnd)
        Notifier.post(title: "Pomodoro complete", body: "Finished: \(goal)\nBreak time.")

        sleepUntil(breakEnd)
        Notifier.post(title: "Break over", body: "Ready for another session?")

        clearEverything()
    }

    static func stop() {
        guard let state = PomodoroState.current else {
            print("focus: no pomodoro running")
            return
        }
        if state.pid > 0 && isPIDAlive(state.pid) {
            _ = kill(state.pid, SIGTERM)
            // Wait up to a second for the daemon to exit on its own.
            for _ in 0..<10 {
                usleep(100_000)
                if !isPIDAlive(state.pid) { break }
            }
        }
        // Daemon doesn't clean up on SIGTERM (no handler), so do it here.
        clearEverything()
        print("focus: pomodoro stopped")
    }

    private static func clearEverything() {
        _ = Subprocess.run("/usr/bin/sudo", ["-n", Paths.selfExecutable.path, "unblock"])
        _ = Subprocess.run(Paths.selfExecutable.path, ["music", "--stop"])
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
            return "focus: no music source. Pass a preset name, --uri, --file, or set FOCUS_SPOTIFY_URI. See `focus music --list`."
        }
    }
}
