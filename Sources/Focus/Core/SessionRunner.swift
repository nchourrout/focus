import Foundation

/// The outside world, as the pomodoro run loop needs it.
///
/// Two adapters justify the seam: `LiveSessionEffects` (sudo-spawned block
/// commands, real playback, wall clock) in the daemon, and a recording fake with
/// a virtual clock in the tests. Before this existed, the loop read
/// `Defaults` directly, slept on the real clock, and shelled out to sudo, so
/// nothing about it could be exercised without waiting 25 minutes for a password
/// prompt.
protocol SessionEffects {
    var now: TimeInterval { get }
    /// Read at every phase boundary, never cached — see `PomodoroCadence`.
    var cadence: PomodoroCadence { get }
    func sleep(until deadline: TimeInterval)
    func applyBlock()
    func removeBlock()
    func startMusic(_ station: Station)
    func stopMusic()
}

/// The pomodoro run loop: sleep to the work deadline, lift the block for the
/// break, and either stop or roll into the next session.
///
/// This is the behaviour a user actually notices — when the block lifts, when
/// the long break lands, whether a set stops and asks. It lives behind one small
/// interface so all of it is reachable from a test.
struct SessionRunner {
    let plan: PomodoroPlan
    let session: PomodoroSession
    let effects: SessionEffects
    /// Non-nil in the daemon, where finished work phases land in the history
    /// log; nil elsewhere (tests, teardown-only construction). Kept optional
    /// so the log stays a daemon concern rather than an effect every caller
    /// must fake.
    var history: SessionHistory?

    /// Tear down everything a run leaves behind. `unblock` is false for a session
    /// that never blocked, which spares a `sudo -n` call (and the matching prompt
    /// if the sudoers drop-in weren't installed).
    ///
    /// Static because `PomodoroDaemon` ends sessions it never ran: a stale one at
    /// launch, and the one `stop` signals.
    static func endSession(unblock: Bool, clearing session: PomodoroSession, effects: SessionEffects) {
        if unblock { effects.removeBlock() }
        effects.stopMusic()
        session.clear()
    }

    /// Append a `completed: false` history line when a run is torn down in the
    /// middle of a work phase (`pomodoro stop`, SIGTERM). Call before
    /// `endSession` — the state file is the source being read. Breaks and
    /// set-complete markers never get partials: their work phase already
    /// earned its line at the boundary. Paused sessions skip too — `pause`
    /// calls this itself before stamping the record, so by the time it reads
    /// paused the line exists and a second one would double-count. The dedupe
    /// check covers the race where the runner recorded the completion just
    /// before we tore down. Stale-file recovery skips this entirely:
    /// a crashed daemon's elapsed time is unknowable, so no fabricated entry.
    static func recordPartialIfNeeded(clearing session: PomodoroSession, now: TimeInterval,
                                      history: SessionHistory = .default) {
        guard let active = session.current else { return }
        guard active.pausedAt == nil else { return }
        guard session.phase(of: active, at: now).phase == .work else { return }
        guard !history.isAlreadyRecorded(startedAt: active.startedAt, goal: active.goal) else { return }
        history.append(SessionHistory.Entry(
            goal: active.goal,
            startedAt: active.startedAt,
            endedAt: min(now, active.workEnd),
            longBreak: active.isLongBreak,
            completed: false
        ))
    }

    /// Write state, and say so when it doesn't take. A failed save leaves the
    /// menu bar showing a session that has already moved on, which is confusing
    /// in a way that is impossible to diagnose from the outside. The run carries
    /// on either way: its own deadlines are in memory.
    private static func save(_ active: PomodoroSession.Active,
                             to session: PomodoroSession, what: String) {
        do {
            try session.save(active)
        } catch {
            Log.daemon.error(
                "failed to write \(what, privacy: .public) to \(session.stateURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Run until the session ends. Blocks the calling thread for the duration,
    /// which is why the daemon is a detached process.
    ///
    /// Design notes:
    /// - The block covers work phases only: it's lifted at the start of each
    ///   break so the user can browse freely while resting, then re-applied when
    ///   the next work phase begins.
    /// - When the cadence says to keep cycling, the loop asks `PomodoroSession`
    ///   for the next iteration, rewrites the state file, and starts a fresh work
    ///   phase with the same goal. Music carries over so playback isn't restarted.
    func run(workEnd: TimeInterval, breakEnd: TimeInterval) {
        // Resuming into a break (`pomodoro resume` on a session paused while
        // resting) hands us a work deadline that is already behind us. That
        // work phase ran, and was recorded, before the pause — replaying it
        // here would re-apply the block for an instant and append a phantom
        // history line ending before it started. Skip straight to the rest.
        var skippingWorkPhase = effects.now >= workEnd

        if plan.block, !skippingWorkPhase { effects.applyBlock() }
        if let station = plan.station { effects.startMusic(station) }

        var currentWorkEnd = workEnd
        var currentBreakEnd = breakEnd

        while true {
            if !skippingWorkPhase {
                effects.sleep(until: currentWorkEnd)

                // One history line per finished work phase. `session.current`
                // still holds this phase's record until the loop rolls the next
                // one, so its startedAt/workEnd bracket exactly what was worked.
                if let history, let cur = session.current {
                    history.append(SessionHistory.Entry(
                        goal: cur.goal,
                        startedAt: cur.startedAt,
                        endedAt: min(effects.now, cur.workEnd),
                        longBreak: cur.isLongBreak,
                        completed: true
                    ))
                }

                // Stop-after-set: when cycling is on and the user opted to stop at
                // each set boundary (every Nth session — the same cadence that earns
                // the long break), end here without taking the final break. Clean up
                // as a normal stop, then leave a terminal marker so the menu bar app
                // posts the "start another set" notification.
                let atWorkEnd = effects.cadence
                if atWorkEnd.keepCycling, atWorkEnd.stopAfterSet,
                   let prev = session.current,
                   session.hasLongBreak(sessionNumber: prev.sessionNumber,
                                        every: atWorkEnd.sessionsBeforeLongBreak) {
                    Self.endSession(unblock: plan.block, clearing: session, effects: effects)
                    Self.save(session.completedSet(from: prev, at: effects.now),
                              to: session, what: "set-complete marker")
                    return
                }

                // Entering the break: lift the block so the user can browse freely
                // while resting. Re-applied when the next work phase begins.
                if plan.block { effects.removeBlock() }
            }
            // Only the first pass can inherit a spent work deadline.
            skippingWorkPhase = false

            effects.sleep(until: currentBreakEnd)

            // Re-read rather than reusing `atWorkEnd`: a whole break has passed,
            // and flipping cycling off during it should take effect now.
            let atBreakEnd = effects.cadence
            if !atBreakEnd.keepCycling { break }

            // If the state file vanished mid-loop (e.g. `pomodoro stop` raced
            // with the break→work transition), bail out instead of writing a
            // phantom next session.
            guard let prev = session.current else { break }

            let next = session.nextSession(
                after: prev,
                workMinutes: plan.workMinutes, breakMinutes: plan.breakMinutes,
                longBreakMinutes: atBreakEnd.longBreakMinutes,
                sessionsBeforeLongBreak: atBreakEnd.sessionsBeforeLongBreak,
                at: effects.now
            )
            Self.save(next, to: session, what: "session \(next.sessionNumber)")
            currentWorkEnd = next.workEnd
            currentBreakEnd = next.breakEnd
            // Next work phase is starting now — restore the block.
            if plan.block { effects.applyBlock() }
        }

        // The block was already lifted at the last break boundary, so this unblock
        // is normally redundant. Keep it anyway as a safety net: if that
        // break-time removeBlock() silently failed (transient sudo error), this
        // is the last chance to clear the block before the session ends.
        // removeBlock() is idempotent, so the redundant case is harmless.
        Self.endSession(unblock: plan.block, clearing: session, effects: effects)
    }
}

/// The real world: `sudo -n` block commands, direct playback control, settings
/// read from `UserDefaults`, and the wall clock.
struct LiveSessionEffects: SessionEffects {
    var now: TimeInterval { Date().timeIntervalSince1970 }
    var cadence: PomodoroCadence { .fromSettings }

    /// Sleep to an absolute wall-clock deadline.
    ///
    /// Sliced rather than one long `Thread.sleep` because that call measures
    /// uptime, which freezes while a Mac sleeps: close the lid mid-work-phase
    /// and the single sleep would keep counting after wake, firing the
    /// work→break transition minutes late while the menu bar (wall-clock
    /// derived) already shows the break. Recomputing the remainder every five
    /// seconds bounds any such drift to one slice.
    func sleep(until deadline: TimeInterval) {
        let slice: TimeInterval = 5
        while true {
            let remaining = deadline - now
            guard remaining > 0 else { return }
            Thread.sleep(forTimeInterval: min(remaining, slice))
        }
    }

    /// Apply the site block (plus DoH suppression) via sudo.
    ///
    /// A failure here is the quietest thing Focus can do wrong: the session runs
    /// normally, the state file says `block: true`, and the sites stay reachable.
    /// The UI can't surface it — the daemon has no NSApplication — so the log is
    /// the only trace. It captures stderr too, since `sudo` explains itself there
    /// ("a password is required" reads very differently from a missing binary).
    func applyBlock() {
        let result = Shell.run(Shell.Command(
            Paths.selfExecutable,
            ["block"] + Defaults.dohSuppressionFlags,
            sudo: true,
            captureStderr: true
        ))
        guard result.status != 0 else { return }
        Log.daemon.error(
            """
            sudo -n block failed (status \(result.status, privacy: .public)); \
            sites are NOT blocked. Is /etc/sudoers.d/focus installed and does it \
            list \(Paths.selfExecutable.path, privacy: .public)? \
            stderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)
            """
        )
    }

    /// Lift the site block via sudo. Idempotent — unblocking when nothing is
    /// blocked is a harmless no-op.
    func removeBlock() {
        let result = Shell.run(Shell.Command(
            Paths.selfExecutable, ["unblock"], sudo: true, captureStderr: true
        ))
        guard result.status != 0 else { return }
        Log.daemon.error(
            """
            sudo -n unblock failed (status \(result.status, privacy: .public)); \
            sites may stay blocked after the session ends. \
            stderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)
            """
        )
    }

    /// Playback needs no root, so call Core directly instead of forking the CLI.
    func startMusic(_ station: Station) {
        do {
            try LocalPlayback.play(station)
        } catch {
            // Music is the least of what a session does — log and work on.
            Log.daemon.error(
                "failed to start \(station.label, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func stopMusic() {
        LocalPlayback.stop()
    }
}
