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

@Suite struct DailyTotalsTests {
    private let calendar = Calendar.current
    private var now: Date { calendar.date(bySettingHour: 15, minute: 0, second: 0, of: Date())! }

    private func entry(daysAgo: Int, hour: Int = 10, minutes: Double = 25, completed: Bool = true) -> SessionHistory.Entry {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!.timeIntervalSince1970
        return SessionHistory.Entry(goal: "g", startedAt: start, endedAt: start + minutes * 60,
                                    longBreak: false, completed: completed)
    }

    @Test func oneSlotPerDayTodayLastEmptyDaysIncluded() {
        let daily = SessionHistory.dailyTotals(days: 7, in: [], now: now)
        #expect(daily.count == 7)
        #expect(daily.last?.day == calendar.startOfDay(for: now))
        #expect(daily.first?.day == SessionHistory.windowStart(days: 7, now: now))
        #expect(daily.allSatisfy { $0.totals.minutes == 0 })
    }

    @Test func entriesLandOnTheDayTheyEnded() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 0, hour: 11),
                       entry(daysAgo: 2, completed: false), entry(daysAgo: 9)]
        let daily = SessionHistory.dailyTotals(days: 7, in: entries, now: now)
        #expect(daily[6].totals == .init(sessions: 2, minutes: 50))
        #expect(daily[4].totals == .init(sessions: 0, minutes: 25), "a partial counts minutes, not a session")
        #expect(daily.reduce(0) { $0 + $1.totals.minutes } == 75, "outside the window is dropped")
    }

    @Test func summaryIsSingularForOneSession() {
        #expect(SessionHistory.Totals(sessions: 1, minutes: 25).summary() == "25m across 1 session")
        #expect(SessionHistory.Totals(sessions: 2, minutes: 75).summary() == "1h 15m across 2 sessions")
    }

    /// Santiago moves its clocks forward at midnight, so 2025-09-07 starts at
    /// 01:00. A window starting that day must still key the days after it on
    /// their own starts, or every entry after it misses its bar.
    @Test func dailyTotalsSurviveDSTStartingAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        let now = try #require(calendar.date(from: DateComponents(year: 2025, month: 9, day: 10, hour: 12)))
        let ended = try #require(calendar.date(from: DateComponents(year: 2025, month: 9, day: 9, hour: 10)))
        let entries = [SessionHistory.Entry(goal: "g", startedAt: ended.timeIntervalSince1970 - 25 * 60,
                                            endedAt: ended.timeIntervalSince1970, longBreak: false, completed: true)]

        let daily = SessionHistory.dailyTotals(days: 4, in: entries, now: now, calendar: calendar)

        let days = daily.map { $0.day }
        let minutes = daily.reduce(0) { $0 + $1.totals.minutes }
        #expect(days == days.map { calendar.startOfDay(for: $0) })
        #expect(minutes == 25)
    }
}
