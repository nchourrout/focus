import Testing
import Foundation
@testable import Focus

@Suite struct SessionHistoryTests {

    /// A SessionHistory pointed at a fresh tmp file.
    private func makeSandbox() throws -> (history: SessionHistory, url: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("session-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("history.jsonl")
        return (SessionHistory(url: url), url)
    }

    private func entry(goal: String = "write spec", startedAt: TimeInterval,
                       minutes: Double, longBreak: Bool = false, completed: Bool = true
    ) -> SessionHistory.Entry {
        SessionHistory.Entry(
            goal: goal, startedAt: startedAt,
            endedAt: startedAt + minutes * 60,
            longBreak: longBreak, completed: completed
        )
    }

    // MARK: Append / read

    @Test func appendThenReadRoundtrips() throws {
        let (history, _) = try makeSandbox()
        let e1 = entry(startedAt: 1000, minutes: 25)
        let e2 = entry(startedAt: 2000, minutes: 25, longBreak: true)

        history.append(e1)
        history.append(e2)

        #expect(history.entries() == [e1, e2], "one JSON object per line, oldest first")
    }

    @Test func appendCreatesParentDirectory() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("history-missing-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("nested/history.jsonl")
        let history = SessionHistory(url: url)
        history.append(entry(startedAt: 1000, minutes: 5))
        #expect(history.entries().count == 1)
        try FileManager.default.removeItem(at: dir)
    }

    @Test func missingFileReadsEmpty() throws {
        let (history, _) = try makeSandbox()
        #expect(history.entries() == [])
    }

    @Test func corruptLinesAreSkippedNotFatal() throws {
        let (history, url) = try makeSandbox()
        let good = try #require(String(
            data: try JSONEncoder().encode(entry(startedAt: 1000, minutes: 25)),
            encoding: .utf8
        ))
        try "\(good)\n{torn line from a crash\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(history.entries().count == 1, "garbage lines never poison the log")
    }

    // MARK: Dedupe guard for the stop() race

    @Test func isAlreadyRecordedMatchesOnlyCompletions() throws {
        let (history, _) = try makeSandbox()
        history.append(entry(startedAt: 1000, minutes: 10))
        history.append(entry(startedAt: 2000, minutes: 3, completed: false))

        #expect(history.isAlreadyRecorded(startedAt: 1000, goal: "write spec"))
        #expect(!history.isAlreadyRecorded(startedAt: 2000, goal: "write spec"),
                "a partial must not mask a later real completion")
        #expect(!history.isAlreadyRecorded(startedAt: 9999, goal: "write spec"))
        #expect(!history.isAlreadyRecorded(startedAt: 1000, goal: "other"))
    }

    // MARK: Aggregation (pure)

    private static let now: TimeInterval = 1_000_000

    @Test func totalsCountsCompletedSessionsAndAllMinutes() {
        let entries = [
            entry(startedAt: Self.now - 3600, minutes: 25),
            entry(startedAt: Self.now - 1800, minutes: 7, completed: false),
            entry(startedAt: Self.now - 60, minutes: 25),
        ]
        let totals = SessionHistory.totals(since: 0, in: entries)
        #expect(totals.sessions == 2, "partials count as focus time, not sessions")
        #expect(totals.minutes == 57)
    }

    @Test func totalsRespectTheCutoff() {
        let cutoff = Self.now - 86_400
        let entries = [
            entry(startedAt: cutoff - 7200, minutes: 25),   // ended before the window
            entry(startedAt: cutoff + 60, minutes: 50),     // inside
        ]
        let totals = SessionHistory.totals(since: cutoff, in: entries)
        #expect(totals.sessions == 1)
        #expect(totals.minutes == 50)
    }

    @Test func describeFormatsDurations() {
        #expect(SessionHistory.Totals(sessions: 0, minutes: 0).describe() == "0m")
        #expect(SessionHistory.Totals(sessions: 1, minutes: 45).describe() == "45m")
        #expect(SessionHistory.Totals(sessions: 2, minutes: 75).describe() == "1h 15m")
        #expect(SessionHistory.Totals(sessions: 3, minutes: 120).describe() == "2h")
    }
}
