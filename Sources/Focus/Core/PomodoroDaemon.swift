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
            // A paused record has no live daemon by design, so the liveness probe
            // below would read it as leftover and silently discard a session the
            // user means to come back to.
            if existing.pausedAt != nil {
                throw CLIError.alreadyPaused
            }
            // Verify the PID is both alive *and* actually our daemon, to guard against
            // PID recycling (a long-running process reusing the dead daemon's PID).
            if isOurProcess(pid: existing.pid, expectedStart: existing.daemonIdentity) {
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
        try spawn(active: first)

        print("focus: pomodoro started — \(plan.workMinutes)min work, \(plan.breakMinutes)min break — \(plan.goal)")
    }

    /// Freeze the running session: tear down the daemon (block lifts, music
    /// stops) but keep the record on disk, marked paused, so `resume` can
    /// rebuild deadlines and spawn a fresh daemon.
    static func pause() {
        let session = PomodoroSession.default
        guard let current = session.current,
              !SessionStaleness.isStale(current)
        else {
            print("focus: no pomodoro running")
            return
        }
        guard current.pausedAt == nil else {
            print("focus: pomodoro is already paused")
            return
        }
        guard session.phase(of: current).phase != .done else {
            print("focus: pomodoro already finished its phases")
            return
        }

        let now = Date().timeIntervalSince1970
        // Bank the focus earned so far, while the record still reads as
        // running. `resume` restarts `startedAt` so the pause gap never counts
        // as focus — which also means the minutes before the pause belong to
        // no later entry. This partial is the only thing that keeps them, and
        // it is disjoint from the entry the resumed phase writes.
        SessionRunner.recordPartialIfNeeded(clearing: session, now: now)
        let frozen = session.paused(current, at: now)
        // Mark the file BEFORE signalling so the dying daemon's partial-history
        // recorder sees the pause and skips it — the line above already covers
        // this phase. The daemon sleeps mid-phase and writes only at
        // boundaries, so nothing races this write; its teardown then clears the
        // file, which we re-save below once it's gone.
        try? session.save(frozen)
        terminateDaemon(current)
        // Belt for a daemon that lost the signal race, mirroring stop().
        SessionRunner.endSession(unblock: current.block, clearing: session,
                                 effects: LiveSessionEffects())
        try? session.save(frozen)
        print("focus: pomodoro paused — resume with 'focus pomodoro resume'")
    }

    /// Continue a paused session: shift the stored deadlines by the elapsed
    /// gap and spawn a fresh daemon for them.
    static func resume() throws {
        let session = PomodoroSession.default
        // `resumed` returns nil for anything that isn't paused, which is the
        // same condition the message describes — one guard covers both.
        guard let paused = session.current, let resumed = session.resumed(paused) else {
            print("focus: no paused pomodoro")
            return
        }
        if paused.pid > 0, isOurProcess(pid: paused.pid, expectedStart: paused.daemonIdentity) {
            print("focus: pomodoro daemon unexpectedly alive; stop it before resuming")
            return
        }
        try spawn(active: resumed)
        print("focus: pomodoro resumed")
    }

    /// End the running break early and start the next work phase now.
    ///
    /// The replacement daemon replays the run's stored plan minutes rather
    /// than re-reading Settings: work/break lengths are fixed for the duration
    /// of one run (see `PomodoroPlan`). Only the cadence is read fresh,
    /// matching how every other phase boundary behaves.
    static func skipBreak() throws {
        let session = PomodoroSession.default
        guard let current = session.current,
              !SessionStaleness.isStale(current)
        else {
            print("focus: no pomodoro running")
            return
        }
        guard session.phase(of: current).phase == .break else {
            print("focus: not in a break — skip only works while resting")
            return
        }
        let cadence = PomodoroCadence.fromSettings
        let next = session.nextSession(
            after: current,
            workMinutes: current.effectiveWorkMinutes,
            breakMinutes: current.effectiveBreakMinutes,
            longBreakMinutes: cadence.longBreakMinutes,
            sessionsBeforeLongBreak: cadence.sessionsBeforeLongBreak,
            at: Date().timeIntervalSince1970
        )

        // Hand the run over rather than stopping it. The old daemon tears down
        // its block (a no-op mid-break) but leaves playback alone, and the
        // replacement adopts the stream already running on the same station, so
        // skipping a break is silent in the audio. Fading out and reconnecting
        // to land on the same station was the loudest thing skip-break did.
        terminateDaemon(current, keepingMusic: true)
        // Belt for a daemon that lost the signal race (same as stop()).
        SessionRunner.endSession(unblock: current.block, stopMusic: false,
                                 clearing: session, effects: LiveSessionEffects())
        try spawn(active: next)
        print("focus: break skipped — starting session \(next.sessionNumber)")
    }

    /// Signal the daemon behind `state` and wait up to a second for it to go.
    ///
    /// `keepingMusic` picks which signal, and so which teardown the daemon runs:
    /// SIGTERM stops everything, SIGUSR1 asks for a handoff that leaves playback
    /// running for the successor. A daemon from a build that predates SIGUSR1
    /// handling dies on its default disposition without cleaning up at all,
    /// which lands in the same place by accident: the caller's `endSession` belt
    /// does the unblock, and the music it never touched carries on.
    ///
    /// Only signal if the PID is still ours; skip if the PID has been recycled.
    /// The `pid > 0` check is a defensive belt: `kill(0, SIGTERM)` would signal
    /// every process in our process group. Callers follow this with their own
    /// `endSession` belt for a daemon that lost the signal race.
    private static func terminateDaemon(_ state: PomodoroSession.Active,
                                        keepingMusic: Bool = false) {
        guard state.pid > 0,
              isOurProcess(pid: state.pid, expectedStart: state.daemonIdentity) else { return }
        _ = kill(state.pid, keepingMusic ? SIGUSR1 : SIGTERM)
        for _ in 0..<10 {
            usleep(100_000)
            if !isPIDAlive(state.pid) { break }
        }
    }

    /// Fork the detached `_pomodoro-run` child for `active` and write the state
    /// file once, with the real PID. Spawn-before-save ordering matters:
    /// writing a placeholder state beforehand opened a window where
    /// `pomodoro stop` could see pid=0, skip the signal, and leak the daemon.
    /// Shared by launch, skipBreak and resume; the plan minutes come off the
    /// record itself, so a caller can't hand the child deadlines that disagree
    /// with the state file it is about to write.
    private static func spawn(active: PomodoroSession.Active) throws {
        var args = [
            "_pomodoro-run",
            "--goal", active.goal,
            "--work-end", String(active.workEnd),
            "--break-end", String(active.breakEnd),
            "--work-minutes", String(active.effectiveWorkMinutes),
            "--break-minutes", String(active.effectiveBreakMinutes),
        ]
        if let uri = active.music {
            args.append(contentsOf: ["--music", uri])
        }
        if !active.block { args.append("--no-block") }
        let handle = try Shell.spawn(Shell.Command(Paths.selfExecutable, args))

        var started = active
        started.pid = handle.pid
        // Stamp the process's own start time, which is what later identifies it.
        // `startedAt` cannot do that job: it moves at every cycle boundary.
        started.daemonStartedAt = pidStartTime(handle.pid)
        try PomodoroSession.default.save(started)
    }

    /// Body of the hidden `_pomodoro-run` subcommand. Runs in the detached child
    /// process, then hands off to `SessionRunner` for the loop itself.
    ///
    /// - We ignore SIGHUP and setsid() ourselves so we survive the parent shell exiting.
    /// - SIGTERM/SIGINT tear the world down through `signalCleanup` rather than
    ///   killing the process raw: with the default disposition, any termination
    ///   outside `pomodoro stop` (a stray kill, an IDE stopping a foreground
    ///   debug run) left the block applied and playback running until the next
    ///   app launch happened to recover it.
    /// - SIGUSR1 is the same teardown minus the music, for `skip-break` handing
    ///   this run to a replacement daemon that keeps playing the same station.
    static func runDaemon(_ plan: PomodoroPlan, workEnd: Double, breakEnd: Double) {
        signal(SIGHUP, SIG_IGN)
        _ = Darwin.setsid()
        installSignalCleanup(plan: plan)

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
            effects: LiveSessionEffects(),
            history: .default
        ).run(workEnd: workEnd, breakEnd: breakEnd)
    }

    static func stop() {
        let session = PomodoroSession.default
        guard let state = session.current else {
            print("focus: no pomodoro running")
            return
        }
        terminateDaemon(state)
        // The daemon now cleans up on SIGTERM itself; this is still the fallback
        // for a daemon that ignored or lost the race, and it's what clears the
        // state when the pid was recycled. Idempotent against signalCleanup.
        SessionRunner.recordPartialIfNeeded(clearing: session, now: Date().timeIntervalSince1970)
        SessionRunner.endSession(unblock: state.block, clearing: session,
                                 effects: LiveSessionEffects())
        print("focus: pomodoro stopped")
    }

    // MARK: Signal teardown

    /// SIGUSR1 is the handoff: the same cleanup, but playback stays up for the
    /// daemon that replaces this one. See `terminateDaemon(_:keepingMusic:)`.
    private static func installSignalCleanup(plan: PomodoroPlan) {
        SignalTraps.install(on: DispatchQueue(label: "focus.daemon.signal"), [
            (SIGTERM, { signalCleanup(plan: plan, keepMusic: false) }),
            (SIGINT, { signalCleanup(plan: plan, keepMusic: false) }),
            (SIGUSR1, { signalCleanup(plan: plan, keepMusic: true) }),
        ])
    }

    /// Runs on the signal queue, while the runner thread may be parked in its
    /// next sleep. Both paths are idempotent (unblock is a no-op on a clean
    /// hosts file, stopMusic kills nothing twice), so racing the runner's own
    /// teardown is harmless; `exit` ends whichever loses.
    private static func signalCleanup(plan: PomodoroPlan, keepMusic: Bool) {
        Log.daemon.notice(
            "terminating on signal; cleaning up (music \(keepMusic ? "kept" : "stopped", privacy: .public))"
        )
        let session = PomodoroSession.default
        SessionRunner.recordPartialIfNeeded(clearing: session, now: Date().timeIntervalSince1970)
        SessionRunner.endSession(
            unblock: plan.block, stopMusic: !keepMusic, clearing: session,
            effects: LiveSessionEffects()
        )
        exit(0)
    }
}

enum CLIError: Error, LocalizedError {
    case alreadyRunning
    case alreadyPaused
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
        case .alreadyPaused:
            return "a pomodoro is paused. Resume it, or stop it first."
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
