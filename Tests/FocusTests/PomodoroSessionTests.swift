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

    @Test func decodeMissingSessionNumberDefaultsOne() throws {
        let legacy = """
        {"goal":"g","pid":1,"started_at":0,"work_end":10,"break_end":20,"music":"","block":true}
        """
        let data = Data(legacy.utf8)
        let decoded = try JSONDecoder().decode(PomodoroSession.Active.self, from: data)
        #expect(decoded.sessionNumber == 1, "files predating session_number decode as session 1")
    }

    @Test func sessionNumberRoundtrips() throws {
        #expect(makeActive().sessionNumber == 1, "makeActive defaults to session 1")
        var s = makeActive()
        s.sessionNumber = 3
        let data = try JSONEncoder().encode(s)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["session_number"] as? Int == 3)
        let decoded = try JSONDecoder().decode(PomodoroSession.Active.self, from: data)
        #expect(decoded.sessionNumber == 3)
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

    @Test func nextSessionAdvancesSessionNumber() throws {
        let (session, _) = try makeSandbox()
        var s = makeActive()
        #expect(s.sessionNumber == 1)
        s = session.nextSession(after: s, workMinutes: 25, breakMinutes: 5, at: 0)
        #expect(s.sessionNumber == 2)
        s = session.nextSession(after: s, workMinutes: 25, breakMinutes: 5, at: 0)
        #expect(s.sessionNumber == 3)
    }

    // MARK: Long-break cadence

    @Test func longBreakLandsOnEveryNthSession() throws {
        let (session, _) = try makeSandbox()
        // every == 4: sessions 4, 8, 12 earn the long break; the rest are short.
        for n in 1...12 {
            let expected = (n % 4 == 0)
            #expect(session.hasLongBreak(sessionNumber: n, every: 4) == expected,
                    "session \(n) long-break expectation")
        }
    }

    @Test func everyZeroDisablesLongBreaks() throws {
        let (session, _) = try makeSandbox()
        #expect(!session.hasLongBreak(sessionNumber: 4, every: 0))
        // With long breaks disabled, rolling never flips isLongBreak or lengthens it.
        var s = makeActive(workEnd: 0, breakEnd: 0)
        s.sessionNumber = 3
        let next = session.nextSession(after: s, workMinutes: 25, breakMinutes: 5, at: 1000)
        #expect(!next.isLongBreak)
        #expect(next.breakEnd == next.workEnd + 5 * 60)
    }

    @Test func nextSessionRollsLongBreakOnCadence() throws {
        let (session, _) = try makeSandbox()
        // prev is session 3; rolling forward produces session 4, which earns the
        // 15-minute long break instead of the 5-minute short one, and records it.
        var s = makeActive(workEnd: 0, breakEnd: 0)
        s.sessionNumber = 3
        let next = session.nextSession(
            after: s, workMinutes: 25, breakMinutes: 5,
            longBreakMinutes: 15, sessionsBeforeLongBreak: 4, at: 1000
        )
        #expect(next.sessionNumber == 4)
        #expect(next.isLongBreak, "session 4 is flagged as a long break")
        #expect(next.workEnd == 1000 + 25 * 60)
        #expect(next.breakEnd == next.workEnd + 15 * 60, "session 4 gets the long break")

        // Session 3 (non-boundary) stays short and unflagged.
        var t = makeActive(workEnd: 0, breakEnd: 0)
        t.sessionNumber = 2
        let three = session.nextSession(
            after: t, workMinutes: 25, breakMinutes: 5,
            longBreakMinutes: 15, sessionsBeforeLongBreak: 4, at: 1000
        )
        #expect(!three.isLongBreak)
        #expect(three.breakEnd == three.workEnd + 5 * 60)
    }

    // MARK: Stop-after-set marker

    @Test func completedSetMarksDoneAndCarriesContext() throws {
        let (session, _) = try makeSandbox()
        var prev = makeActive(
            goal: "ship", pid: 777, startedAt: 100,
            workEnd: 1600, breakEnd: 1900, music: "soma", block: false
        )
        prev.sessionNumber = 4
        prev.isLongBreak = true

        let marker = session.completedSet(from: prev, at: 1600)
        #expect(marker.setComplete)
        // Both deadlines pulled back to `at`, so the phase reads .done.
        #expect(marker.workEnd == 1600)
        #expect(marker.breakEnd == 1600)
        #expect(session.phase(of: marker, at: 1600).phase == .done)
        // Goal/pid/music/block/session carry over for the "start another set" prompt.
        #expect(marker.goal == prev.goal)
        #expect(marker.pid == prev.pid)
        #expect(marker.music == prev.music)
        #expect(marker.block == prev.block)
        #expect(marker.sessionNumber == prev.sessionNumber)
    }

    @Test func setCompleteDefaultsFalseAndRoundtrips() throws {
        // Files predating the field decode as false.
        let legacy = """
        {"goal":"g","pid":1,"started_at":0,"work_end":10,"break_end":20,"music":""}
        """
        let decodedLegacy = try JSONDecoder().decode(
            PomodoroSession.Active.self, from: Data(legacy.utf8)
        )
        #expect(!decodedLegacy.setComplete)

        // And a true value survives an encode/decode round-trip.
        let (session, _) = try makeSandbox()
        let marker = session.completedSet(from: makeActive(), at: 0)
        let data = try JSONEncoder().encode(marker)
        let decoded = try JSONDecoder().decode(PomodoroSession.Active.self, from: data)
        #expect(decoded.setComplete)
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
