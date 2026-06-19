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

        enum CodingKeys: String, CodingKey {
            case goal, pid, music, block
            case startedAt = "started_at"
            case workEnd = "work_end"
            case breakEnd = "break_end"
            case sessionNumber = "session_number"
            case isLongBreak = "is_long_break"
        }

        init(goal: String, pid: Int32, startedAt: TimeInterval,
             workEnd: TimeInterval, breakEnd: TimeInterval,
             music: String?, block: Bool,
             sessionNumber: Int = 1, isLongBreak: Bool = false) {
            self.goal = goal
            self.pid = pid
            self.startedAt = startedAt
            self.workEnd = workEnd
            self.breakEnd = breakEnd
            self.music = music
            self.block = block
            self.sessionNumber = sessionNumber
            self.isLongBreak = isLongBreak
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            goal = try c.decode(String.self, forKey: .goal)
            pid = try c.decode(Int32.self, forKey: .pid)
            startedAt = try c.decode(TimeInterval.self, forKey: .startedAt)
            workEnd = try c.decode(TimeInterval.self, forKey: .workEnd)
            breakEnd = try c.decode(TimeInterval.self, forKey: .breakEnd)
            let raw = try c.decodeIfPresent(String.self, forKey: .music) ?? ""
            music = raw.isEmpty ? nil : raw
            block = try c.decodeIfPresent(Bool.self, forKey: .block) ?? true
            sessionNumber = try c.decodeIfPresent(Int.self, forKey: .sessionNumber) ?? 1
            isLongBreak = try c.decodeIfPresent(Bool.self, forKey: .isLongBreak) ?? false
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
            sessionNumber: sessionNumber, isLongBreak: long
        )
    }
}

// PID liveness helpers are in PIDLiveness.swift — used by both this module
// (daemon process tracking) and LocalPlayback (music-PID cleanup).
