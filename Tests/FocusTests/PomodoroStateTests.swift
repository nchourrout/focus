import Testing
import Foundation
@testable import Focus

@Suite struct PomodoroStateTests {
    @Test func jsonKeysMatchPythonSchema() throws {
        let state = PomodoroState(
            goal: "test", pid: 1234, startedAt: 1000,
            workEnd: 2500, breakEnd: 2800, music: "https://example.com/stream.mp3", block: true
        )
        let data = try JSONEncoder().encode(state)
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(obj["goal"] as? String == "test")
        #expect(obj["pid"] as? Int == 1234)
        #expect(obj["started_at"] as? Double == 1000)
        #expect(obj["work_end"] as? Double == 2500)
        #expect(obj["break_end"] as? Double == 2800)
        #expect(obj["music"] as? String == "https://example.com/stream.mp3")
    }

    @Test func roundtripDecode() throws {
        let state = PomodoroState(
            goal: "g", pid: 42, startedAt: 1, workEnd: 2, breakEnd: 3, music: "", block: true
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PomodoroState.self, from: data)
        #expect(decoded.goal == state.goal)
        #expect(decoded.pid == state.pid)
        #expect(decoded.workEnd == state.workEnd)
    }

    @Test func phaseLogic() {
        let s = PomodoroState(goal: "", pid: 0, startedAt: 0, workEnd: 100, breakEnd: 200, music: "", block: true)
        #expect(s.phase(at: 50).phase == .work)
        #expect(s.phase(at: 50).timeLeft == 50)
        #expect(s.phase(at: 150).phase == .break)
        #expect(s.phase(at: 150).timeLeft == 50)
        #expect(s.phase(at: 300).phase == .done)
    }

    @Test func pidAliveOnSelf() {
        #expect(isPIDAlive(getpid()))
        #expect(!isPIDAlive(-1))
        #expect(!isPIDAlive(0))
    }

    @Test func pidStartTimeMatchesSelf() throws {
        let start = try #require(pidStartTime(getpid()))
        // Our own process started in the past, definitely before "now + 1s".
        #expect(start < Date().timeIntervalSince1970 + 1)
        // And not way in the past (sanity floor: not before 2020).
        #expect(start > 1_577_836_800)
    }

    @Test func isOurProcessDetectsPIDRecycling() throws {
        let pid = getpid()
        let actualStart = try #require(pidStartTime(pid))
        // A start-time within tolerance: this *is* our process.
        #expect(isOurProcess(pid: pid, expectedStart: actualStart))
        // A start-time far from the actual one: PID is alive but identity differs.
        #expect(!isOurProcess(pid: pid, expectedStart: actualStart - 10_000))
        // A definitely-dead PID: not ours.
        #expect(!isOurProcess(pid: -1, expectedStart: actualStart))
    }
}
