import Foundation
import Darwin

/// On-disk pomodoro state. JSON schema is wire-compatible with the previous Python tool
/// (snake_case keys, `music` is always present — empty string for "no music").
struct PomodoroState: Codable {
    let goal: String
    var pid: Int32
    let startedAt: TimeInterval
    let workEnd: TimeInterval
    let breakEnd: TimeInterval
    /// nil internally; serialized as "" to stay compatible with the Python schema.
    var music: String?

    enum CodingKeys: String, CodingKey {
        case goal, pid, music
        case startedAt = "started_at"
        case workEnd = "work_end"
        case breakEnd = "break_end"
    }

    init(goal: String, pid: Int32, startedAt: TimeInterval, workEnd: TimeInterval, breakEnd: TimeInterval, music: String?) {
        self.goal = goal
        self.pid = pid
        self.startedAt = startedAt
        self.workEnd = workEnd
        self.breakEnd = breakEnd
        self.music = music
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(goal, forKey: .goal)
        try c.encode(pid, forKey: .pid)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(workEnd, forKey: .workEnd)
        try c.encode(breakEnd, forKey: .breakEnd)
        try c.encode(music ?? "", forKey: .music)
    }

    enum Phase: String {
        case work, `break`, done
    }

    func phase(at now: TimeInterval = Date().timeIntervalSince1970) -> (phase: Phase, timeLeft: TimeInterval) {
        if now < workEnd { return (.work, workEnd - now) }
        if now < breakEnd { return (.break, breakEnd - now) }
        return (.done, 0)
    }

    static var current: PomodoroState? {
        guard let data = try? Data(contentsOf: Paths.pomodoroState) else { return nil }
        return try? JSONDecoder().decode(PomodoroState.self, from: data)
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Paths.pomodoroState, options: .atomic)
    }

    static func clearFile() {
        try? FileManager.default.removeItem(at: Paths.pomodoroState)
    }
}

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
