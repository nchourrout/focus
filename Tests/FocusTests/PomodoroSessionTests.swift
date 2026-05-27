import Testing
import Foundation
@testable import Focus

@Suite struct PomodoroSessionTests {

    private func makeActive(
        goal: String = "test", pid: Int32 = 1234,
        startedAt: TimeInterval = 1000,
        workEnd: TimeInterval = 2500, breakEnd: TimeInterval = 2800,
        music: String? = "https://example.com/stream.mp3", block: Bool = true
    ) -> PomodoroSession.Active {
        PomodoroSession.Active(
            goal: goal, pid: pid, startedAt: startedAt,
            workEnd: workEnd, breakEnd: breakEnd, music: music, block: block
        )
    }

    /// Build a PomodoroSession pointed at a fresh tmp state URL.
    private func makeSandbox() throws -> (session: PomodoroSession, stateURL: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pomodoro-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stateURL = dir.appendingPathComponent("state.json")
        return (PomodoroSession(stateURL: stateURL), stateURL)
    }

    // MARK: JSON wire format (must stay compatible with the Python tool + external consumers)

    @Test func jsonKeysMatchPythonSchema() throws {
        let state = makeActive()
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
        let state = makeActive(
            goal: "g", pid: 42, startedAt: 1, workEnd: 2, breakEnd: 3, music: nil, block: true
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PomodoroSession.Active.self, from: data)
        #expect(decoded.goal == state.goal)
        #expect(decoded.pid == state.pid)
        #expect(decoded.workEnd == state.workEnd)
        #expect(decoded.music == nil, "empty-string music decodes back to nil")
    }

    @Test func decodeMissingBlockDefaultsTrue() throws {
        let legacy = """
        {"goal":"g","pid":1,"started_at":0,"work_end":10,"break_end":20,"music":""}
        """
        let data = Data(legacy.utf8)
        let decoded = try JSONDecoder().decode(PomodoroSession.Active.self, from: data)
        #expect(decoded.block == true, "files predating the `block` field decode as block=true")
    }

    // MARK: Phase derivation

    @Test func phaseLogic() throws {
        let (session, _) = try makeSandbox()
        let s = makeActive(startedAt: 0, workEnd: 100, breakEnd: 200, music: nil)
        #expect(session.phase(of: s, at: 50).phase == .work)
        #expect(session.phase(of: s, at: 50).timeLeft == 50)
        #expect(session.phase(of: s, at: 150).phase == .break)
        #expect(session.phase(of: s, at: 150).timeLeft == 50)
        #expect(session.phase(of: s, at: 300).phase == .done)
        #expect(session.phase(of: s, at: 300).timeLeft == 0)
    }

    @Test func phaseBoundariesAreHalfOpen() throws {
        let (session, _) = try makeSandbox()
        let s = makeActive(startedAt: 0, workEnd: 100, breakEnd: 200, music: nil)
        // exactly at workEnd → break (work is < workEnd, not <=)
        #expect(session.phase(of: s, at: 100).phase == .break)
        // exactly at breakEnd → done
        #expect(session.phase(of: s, at: 200).phase == .done)
    }

    // MARK: Scheduling

    @Test func deadlinesAddMinutes() throws {
        let (session, _) = try makeSandbox()
        let (workEnd, breakEnd) = session.deadlines(workMinutes: 25, breakMinutes: 5, at: 1000)
        #expect(workEnd == 1000 + 25 * 60)
        #expect(breakEnd == workEnd + 5 * 60)
    }

    @Test func nextSessionCarriesPidGoalMusicBlockAndRollsDeadlines() throws {
        let (session, _) = try makeSandbox()
        let prev = makeActive(
            goal: "ship the thing", pid: 999, startedAt: 0,
            workEnd: 1500, breakEnd: 1800, music: "soma", block: false
        )
        let next = session.nextSession(after: prev, workMinutes: 25, breakMinutes: 5, at: 2000)
        #expect(next.goal == prev.goal)
        #expect(next.pid == prev.pid)
        #expect(next.music == prev.music)
        #expect(next.block == prev.block)
        #expect(next.startedAt == 2000)
        #expect(next.workEnd == 2000 + 25 * 60)
        #expect(next.breakEnd == next.workEnd + 5 * 60)
    }

    // MARK: Persistence — round-trip against an injected stateURL

    @Test func currentIsNilOnMissingFile() throws {
        let (session, _) = try makeSandbox()
        #expect(session.current == nil)
    }

    @Test func saveThenCurrentRoundtrips() throws {
        let (session, _) = try makeSandbox()
        let active = makeActive()
        try session.save(active)
        let loaded = try #require(session.current)
        #expect(loaded == active)
    }

    @Test func clearRemovesFile() throws {
        let (session, stateURL) = try makeSandbox()
        try session.save(makeActive())
        #expect(FileManager.default.fileExists(atPath: stateURL.path))
        session.clear()
        #expect(!FileManager.default.fileExists(atPath: stateURL.path))
        #expect(session.current == nil)
    }

    @Test func clearOnMissingFileIsNoop() throws {
        let (session, _) = try makeSandbox()
        session.clear()  // must not throw
        #expect(session.current == nil)
    }

    // MARK: PID liveness helpers — unchanged semantics

    @Test func pidAliveOnSelf() {
        #expect(isPIDAlive(getpid()))
        #expect(!isPIDAlive(-1))
        #expect(!isPIDAlive(0))
    }

    @Test func pidStartTimeMatchesSelf() throws {
        let start = try #require(pidStartTime(getpid()))
        #expect(start < Date().timeIntervalSince1970 + 1)
        #expect(start > 1_577_836_800)
    }

    @Test func isOurProcessDetectsPIDRecycling() throws {
        let pid = getpid()
        let actualStart = try #require(pidStartTime(pid))
        #expect(isOurProcess(pid: pid, expectedStart: actualStart))
        #expect(!isOurProcess(pid: pid, expectedStart: actualStart - 10_000))
        #expect(!isOurProcess(pid: -1, expectedStart: actualStart))
    }
}
