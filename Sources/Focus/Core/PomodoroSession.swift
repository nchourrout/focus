import Foundation

/// The pomodoro lifecycle: persisted state, deadline math, phase derivation.
///
/// Owns the JSON-on-disk format (wire-compatible with the previous Python tool;
/// snake_case keys, `music` always present as empty string when nil). Mutation
/// is a single-writer pattern: the daemon process writes, others read.
struct PomodoroSession {
    static let `default` = PomodoroSession(stateURL: Paths.pomodoroState)

    let stateURL: URL

    // MARK: Active session — the on-disk record

    /// One pomodoro in progress. Codable schema is wire-compatible with the
    /// previous Python tool: snake_case keys, `music` always present (empty
    /// string when nil), `block` defaults to true on decode for files written
    /// before that field existed.
    struct Active: Codable, Equatable {
        let goal: String
        var pid: Int32
        let startedAt: TimeInterval
        let workEnd: TimeInterval
        let breakEnd: TimeInterval
        /// The daemon process's own start time, stamped from `pidStartTime` right
        /// after the fork. Nil for records written before this field existed, and
        /// for one that has no daemon yet (paused, or between `resumed` and the
        /// spawn that stamps it). See `daemonIdentity`.
        var daemonStartedAt: TimeInterval?
        /// nil internally; serialized as "" to stay compatible with the Python schema.
        var music: String?
        /// Whether the daemon should block /etc/hosts for the duration of the session.
        var block: Bool
        /// 1-based index of this work phase within the current run. Drives the
        /// long-break cadence (every Nth session earns the longer break) and the
        /// "session 3" affordances in the UI. Files predating this field decode
        /// as 1.
        var sessionNumber: Int
        /// Whether the break that follows this work phase is the long one. Decided
        /// once, when the session is scheduled, so the UI labels the break that was
        /// actually planned — not whatever the cadence setting reads right now (the
        /// user may change it mid-run). Files predating this field decode as false.
        var isLongBreak: Bool
        /// Terminal marker: the daemon set this set's last work phase as the end
        /// of a "stop after each set" run and exited (skipping the final break).
        /// The menu bar app reads it to post the "start another set" notification,
        /// then clears the file. Always false on a live session. Files predating
        /// this field decode as false.
        var setComplete: Bool
        /// Work/break minutes of the plan this run launched with, so commands
        /// acting mid-run (`pomodoro skip-break`) rebuild deadlines faithfully
        /// even when Settings changed since launch — durations are fixed for
        /// the duration of one run (see `PomodoroPlan`). Files predating these
        /// fields decode as nil; callers fall back to current Settings, which
        /// reproduces the pre-schema behaviour.
        var workMinutes: Int?
        var breakMinutes: Int?
        /// Pause marker: non-nil while the session sits paused (daemon torn
        /// down, block lifted, music stopped). The remaining time derives from
        /// the stored deadlines minus this instant, so one field carries the
        /// whole pause state; `resumed(at:)` shifts the deadlines by the
        /// elapsed gap. Files predating it decode as nil (never paused).
        /// While set, the record is intentionally ownerless: staleness probes,
        /// partial-history recording, and dead-daemon recovery all skip it.
        var pausedAt: TimeInterval?

        /// The run's work/break lengths, with the pre-schema fallback applied
        /// once. Files predating `work_minutes`/`break_minutes` decode as nil;
        /// resolving to current Settings here reproduces exactly what those
        /// runs did, and keeps the migration rule in one place instead of at
        /// every command that acts mid-run.
        /// The timestamp that proves `pid` is still this run's daemon, for
        /// `isOurProcess`.
        ///
        /// Not `startedAt`. That is the current work phase's start, and
        /// `nextSession` moves it at every cycle boundary while the very same
        /// daemon keeps running, so from the second session onward it named a
        /// moment the process did not start at. Every question of "is this still
        /// our daemon" then answered no: the menu bar cleared live sessions as
        /// abandoned two seconds into session 2, and `stop`, `pause` and
        /// `skip-break` quietly stopped signalling the daemon at all, leaving it
        /// orphaned. Auto-start is on by default, so this reached every run.
        ///
        /// Falls back to `startedAt` for records written before the field
        /// existed, which is what those builds compared against anyway. Such a
        /// record still misidentifies its daemon past session 1; nothing can
        /// recover the real start time after the fact, and it corrects itself at
        /// the next `pomodoro start`.
        var daemonIdentity: TimeInterval { daemonStartedAt ?? startedAt }

        var effectiveWorkMinutes: Int { workMinutes ?? Defaults.workMinutes }
        var effectiveBreakMinutes: Int { breakMinutes ?? Defaults.breakMinutes }

        enum CodingKeys: String, CodingKey {
            case goal, pid, music, block
            case startedAt = "started_at"
            case daemonStartedAt = "daemon_started_at"
            case workEnd = "work_end"
            case breakEnd = "break_end"
            case sessionNumber = "session_number"
            case isLongBreak = "is_long_break"
            case setComplete = "set_complete"
            case workMinutes = "work_minutes"
            case breakMinutes = "break_minutes"
            case pausedAt = "paused_at"
        }

        init(goal: String, pid: Int32, startedAt: TimeInterval,
             workEnd: TimeInterval, breakEnd: TimeInterval,
             music: String?, block: Bool, daemonStartedAt: TimeInterval? = nil,
             sessionNumber: Int = 1, isLongBreak: Bool = false,
             setComplete: Bool = false,
             workMinutes: Int? = nil, breakMinutes: Int? = nil,
             pausedAt: TimeInterval? = nil) {
            self.goal = goal
            self.pid = pid
            self.startedAt = startedAt
            self.daemonStartedAt = daemonStartedAt
            self.workEnd = workEnd
            self.breakEnd = breakEnd
            self.music = music
            self.block = block
            self.sessionNumber = sessionNumber
            self.isLongBreak = isLongBreak
            self.setComplete = setComplete
            self.workMinutes = workMinutes
            self.breakMinutes = breakMinutes
            self.pausedAt = pausedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            goal = try c.decode(String.self, forKey: .goal)
            pid = try c.decode(Int32.self, forKey: .pid)
            startedAt = try c.decode(TimeInterval.self, forKey: .startedAt)
            daemonStartedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .daemonStartedAt)
            workEnd = try c.decode(TimeInterval.self, forKey: .workEnd)
            breakEnd = try c.decode(TimeInterval.self, forKey: .breakEnd)
            let raw = try c.decodeIfPresent(String.self, forKey: .music) ?? ""
            music = raw.isEmpty ? nil : raw
            block = try c.decodeIfPresent(Bool.self, forKey: .block) ?? true
            sessionNumber = try c.decodeIfPresent(Int.self, forKey: .sessionNumber) ?? 1
            isLongBreak = try c.decodeIfPresent(Bool.self, forKey: .isLongBreak) ?? false
            setComplete = try c.decodeIfPresent(Bool.self, forKey: .setComplete) ?? false
            workMinutes = try c.decodeIfPresent(Int.self, forKey: .workMinutes)
            breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes)
            pausedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .pausedAt)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(goal, forKey: .goal)
            try c.encode(pid, forKey: .pid)
            try c.encode(startedAt, forKey: .startedAt)
            try c.encode(workEnd, forKey: .workEnd)
            try c.encode(breakEnd, forKey: .breakEnd)
            try c.encode(music ?? "", forKey: .music)
            try c.encode(block, forKey: .block)
            try c.encode(sessionNumber, forKey: .sessionNumber)
            try c.encode(isLongBreak, forKey: .isLongBreak)
            try c.encode(setComplete, forKey: .setComplete)
            try c.encodeIfPresent(workMinutes, forKey: .workMinutes)
            try c.encodeIfPresent(breakMinutes, forKey: .breakMinutes)
            try c.encodeIfPresent(pausedAt, forKey: .pausedAt)
            try c.encodeIfPresent(daemonStartedAt, forKey: .daemonStartedAt)
        }
    }

    enum Phase: String {
        case work, `break`, done
    }

    // MARK: Read / write

    var current: Active? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(Active.self, from: data)
    }

    func save(_ active: Active) throws {
        let data = try JSONEncoder().encode(active)
        try data.write(to: stateURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: stateURL)
    }

    // MARK: Phase derivation

    func phase(of active: Active,
               at now: TimeInterval = Date().timeIntervalSince1970)
    -> (phase: Phase, timeLeft: TimeInterval) {
        if now < active.workEnd { return (.work, active.workEnd - now) }
        if now < active.breakEnd { return (.break, active.breakEnd - now) }
        return (.done, 0)
    }

    // MARK: Scheduling

    /// Compute (workEnd, breakEnd) deadlines for a session starting at `at`.
    func deadlines(workMinutes: Int, breakMinutes: Int,
                   at start: TimeInterval = Date().timeIntervalSince1970)
    -> (workEnd: TimeInterval, breakEnd: TimeInterval) {
        let workEnd = start + Double(workMinutes * 60)
        let breakEnd = workEnd + Double(breakMinutes * 60)
        return (workEnd, breakEnd)
    }

    // MARK: Long-break cadence

    /// Whether the break following the 1-based work session `n` is the long
    /// break: every `every`-th session earns it (the classic "long break after
    /// 4 pomodoros"). `every <= 0` disables long breaks entirely.
    func hasLongBreak(sessionNumber n: Int, every: Int) -> Bool {
        every > 0 && n % every == 0
    }

    /// Schedule the first session of a run. Same composed rule as
    /// `nextSession` — session number decides the long break, which decides the
    /// break length, which decides the deadlines — so the two stay in step.
    /// Session 1 only earns a long break if the cadence is "every 1".
    func firstSession(plan: PomodoroPlan, cadence: PomodoroCadence, pid: Int32,
                      at start: TimeInterval = Date().timeIntervalSince1970) -> Active {
        let long = hasLongBreak(sessionNumber: 1, every: cadence.sessionsBeforeLongBreak)
        let (workEnd, breakEnd) = deadlines(
            workMinutes: plan.workMinutes,
            breakMinutes: long ? cadence.longBreakMinutes : plan.breakMinutes,
            at: start
        )
        return Active(
            goal: plan.goal, pid: pid, startedAt: start,
            workEnd: workEnd, breakEnd: breakEnd,
            music: plan.station?.uri, block: plan.block,
            sessionNumber: 1, isLongBreak: long,
            workMinutes: plan.workMinutes, breakMinutes: plan.breakMinutes
        )
    }

    /// Roll an Active into the next iteration of the same session (auto-start).
    /// Goal, pid, music, block are carried over; `sessionNumber` advances and the
    /// break follows the long-break cadence (its length and the recorded
    /// `isLongBreak` flag); deadlines are recomputed from `at`. The pid stays —
    /// the daemon is still the same process.
    func nextSession(after prev: Active, workMinutes: Int, breakMinutes: Int,
                     longBreakMinutes: Int = 0, sessionsBeforeLongBreak: Int = 0,
                     at start: TimeInterval = Date().timeIntervalSince1970) -> Active {
        let sessionNumber = prev.sessionNumber + 1
        let long = hasLongBreak(sessionNumber: sessionNumber, every: sessionsBeforeLongBreak)
        let (workEnd, breakEnd) = deadlines(
            workMinutes: workMinutes, breakMinutes: long ? longBreakMinutes : breakMinutes, at: start
        )
        return Active(
            goal: prev.goal, pid: prev.pid, startedAt: start,
            workEnd: workEnd, breakEnd: breakEnd,
            music: prev.music, block: prev.block,
            // Same process, so its start time carries even though `startedAt`
            // moves to this session.
            daemonStartedAt: prev.daemonStartedAt,
            sessionNumber: sessionNumber, isLongBreak: long,
            workMinutes: workMinutes, breakMinutes: breakMinutes
        )
    }

    /// Terminal marker written when a "stop after each set" run ends: the same
    /// session, with both deadlines pulled back to `at` (so `phase(of:)` reads
    /// `.done`) and `setComplete` flipped on. The menu bar app posts the
    /// "start another set" notification off this and then clears the file.
    func completedSet(from prev: Active,
                      at end: TimeInterval = Date().timeIntervalSince1970) -> Active {
        Active(
            goal: prev.goal, pid: prev.pid, startedAt: prev.startedAt,
            workEnd: end, breakEnd: end,
            music: prev.music, block: prev.block,
            daemonStartedAt: prev.daemonStartedAt,
            // No break follows a set-complete marker, so isLongBreak is moot — keep
            // it false rather than carrying a flag for a break that never happens.
            sessionNumber: prev.sessionNumber, isLongBreak: false,
            setComplete: true,
            workMinutes: prev.workMinutes, breakMinutes: prev.breakMinutes
        )
    }

    // MARK: Pause / resume

    /// Stamp `active` as paused at `now`. The deadlines stay untouched — the
    /// remaining time derives from them minus `pausedAt`, so one field carries
    /// the whole pause state. Callers tear down the daemon around this write:
    /// pausing releases the block (the teardown unblocks) and stops playback.
    func paused(_ active: Active,
                at now: TimeInterval = Date().timeIntervalSince1970) -> Active {
        var copy = active
        copy.pausedAt = now
        return copy
    }

    /// Undo a pause: shift both deadlines forward by the elapsed gap so the
    /// phase and its remaining seconds continue exactly where they left off.
    /// `startedAt` moves to the resume instant too — it brackets the history
    /// entry for this work phase, which should measure focus, not wall-clock
    /// including the pause. Returns nil when `active` isn't paused. The pid is
    /// zeroed; the caller spawns a fresh daemon and stamps its pid.
    func resumed(_ active: Active,
                 at now: TimeInterval = Date().timeIntervalSince1970) -> Active? {
        guard let pausedAt = active.pausedAt else { return nil }
        let delta = max(0, now - pausedAt)
        return Active(
            goal: active.goal,
            pid: 0,
            startedAt: now,
            workEnd: active.workEnd + delta,
            breakEnd: active.breakEnd + delta,
            music: active.music,
            block: active.block,
            daemonStartedAt: nil,
            sessionNumber: active.sessionNumber,
            isLongBreak: active.isLongBreak,
            setComplete: active.setComplete,
            workMinutes: active.workMinutes,
            breakMinutes: active.breakMinutes
        )
    }
}

// PID liveness helpers are in PIDLiveness.swift — used by both this module
// (daemon process tracking) and LocalPlayback (music-PID cleanup).
