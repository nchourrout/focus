import Foundation
import Darwin

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

        enum CodingKeys: String, CodingKey {
            case goal, pid, music, block
            case startedAt = "started_at"
            case workEnd = "work_end"
            case breakEnd = "break_end"
        }

        init(goal: String, pid: Int32, startedAt: TimeInterval,
             workEnd: TimeInterval, breakEnd: TimeInterval,
             music: String?, block: Bool) {
            self.goal = goal
            self.pid = pid
            self.startedAt = startedAt
            self.workEnd = workEnd
            self.breakEnd = breakEnd
            self.music = music
            self.block = block
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

    /// Roll an Active into the next iteration of the same session (auto-start).
    /// Goal, pid, music, block are carried over; deadlines are recomputed from
    /// `at`. The pid stays — the daemon is still the same process.
    func nextSession(after prev: Active, workMinutes: Int, breakMinutes: Int,
                     at start: TimeInterval = Date().timeIntervalSince1970) -> Active {
        let (workEnd, breakEnd) = deadlines(workMinutes: workMinutes,
                                            breakMinutes: breakMinutes, at: start)
        return Active(
            goal: prev.goal, pid: prev.pid, startedAt: start,
            workEnd: workEnd, breakEnd: breakEnd,
            music: prev.music, block: prev.block
        )
    }
}

// MARK: PID liveness — module-level so callers reach them without qualification

/// POSIX-level liveness check. Returns true if the PID names a live process we can
/// address (EPERM counts as alive; the process exists but isn't ours).
func isPIDAlive(_ pid: Int32) -> Bool {
    guard pid > 0 else { return false }
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

/// Returns the process start time (unix timestamp) for a PID, or nil if the
/// process no longer exists. Used to guard against PID recycling before we
/// SIGTERM what we think is our pomodoro daemon.
func pidStartTime(_ pid: Int32) -> TimeInterval? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
    let rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
    guard rc == size else { return nil }
    return TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
}

/// True if the PID is alive AND its start time is within ±1 second of `expectedStart`
/// (process creation timestamps are in seconds; a small tolerance covers rounding).
/// Returning false here means either the process is dead or the PID has been recycled
/// to an unrelated process.
func isOurProcess(pid: Int32, expectedStart: TimeInterval) -> Bool {
    guard isPIDAlive(pid), let actual = pidStartTime(pid) else { return false }
    return abs(actual - expectedStart) < 1.0
}
