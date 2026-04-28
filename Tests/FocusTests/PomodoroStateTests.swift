import Testing
import Foundation
@testable import Focus

@Suite struct PomodoroStateTests {
    @Test func jsonKeysMatchPythonSchema() throws {
        let state = PomodoroState(
            goal: "test", pid: 1234, startedAt: 1000,
            workEnd: 2500, breakEnd: 2800, music: "https://example.com/stream.mp3"
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
            goal: "g", pid: 42, startedAt: 1, workEnd: 2, breakEnd: 3, music: ""
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PomodoroState.self, from: data)
        #expect(decoded.goal == state.goal)
        #expect(decoded.pid == state.pid)
        #expect(decoded.workEnd == state.workEnd)
    }

    @Test func phaseLogic() {
        let s = PomodoroState(goal: "", pid: 0, startedAt: 0, workEnd: 100, breakEnd: 200, music: "")
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
}
