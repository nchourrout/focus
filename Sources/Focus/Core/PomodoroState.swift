import Foundation
import Darwin

/// On-disk pomodoro state. JSON schema is wire-compatible with the previous Python tool.
struct PomodoroState: Codable {
    let goal: String
    var pid: Int32
    let startedAt: TimeInterval
    let workEnd: TimeInterval
    let breakEnd: TimeInterval
    let music: String

    enum CodingKeys: String, CodingKey {
        case goal, pid, music
        case startedAt = "started_at"
        case workEnd = "work_end"
        case breakEnd = "break_end"
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
