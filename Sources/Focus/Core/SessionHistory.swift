import Foundation

/// Append-only log of finished work sessions, one JSON object per line.
///
/// Written by the daemon (the same single-writer discipline as the state
/// file): a line lands when a work phase runs to its deadline, and a partial
/// line with `completed: false` lands when a run is stopped mid-work-phase.
/// Breaks are not work; they never get a line. Appending is best effort —
/// a failed write logs and moves on, exactly like the runner's other saves,
/// because losing a stat must never cost the user their session.
struct SessionHistory {
    static let `default` = SessionHistory(url: Paths.history)

    let url: URL

    struct Entry: Codable, Equatable {
        let goal: String
        let startedAt: TimeInterval
        let endedAt: TimeInterval
        /// Minutes of focus this entry represents, rounded down. Derived, but
        /// still written to the file so it stays human-greppable.
        /// Whether the break that followed earned the long-break cadence.
        let longBreak: Bool
        /// False only for entries written when a run was stopped mid-work-phase.
        let completed: Bool

        enum CodingKeys: String, CodingKey {
            case goal, minutes
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case longBreak = "long_break"
            case completed
        }

        var minutes: Int { max(0, Int((endedAt - startedAt) / 60)) }

        init(goal: String, startedAt: TimeInterval, endedAt: TimeInterval,
             longBreak: Bool, completed: Bool) {
            self.goal = goal
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.longBreak = longBreak
            self.completed = completed
        }

        /// The line a work phase earns: `active`'s own bracket, ending at `at`
        /// clamped to the phase deadline so a teardown that runs a moment late
        /// can't bank minutes the phase never had.
        init(workPhaseOf active: PomodoroSession.Active,
             endedAt at: TimeInterval, completed: Bool) {
            self.init(
                goal: active.goal,
                startedAt: active.startedAt,
                endedAt: min(at, active.workEnd),
                longBreak: active.isLongBreak,
                completed: completed
            )
        }

        /// Decoding needs its own path because `minutes` is derived — ignore
        /// whatever the file stored for it.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            goal = try c.decode(String.self, forKey: .goal)
            startedAt = try c.decode(TimeInterval.self, forKey: .startedAt)
            endedAt = try c.decode(TimeInterval.self, forKey: .endedAt)
            longBreak = try c.decodeIfPresent(Bool.self, forKey: .longBreak) ?? false
            completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? true
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(goal, forKey: .goal)
            try c.encode(startedAt, forKey: .startedAt)
            try c.encode(endedAt, forKey: .endedAt)
            try c.encode(minutes, forKey: .minutes)
            try c.encode(longBreak, forKey: .longBreak)
            try c.encode(completed, forKey: .completed)
        }
    }

    // MARK: Write / read

    func append(_ entry: Entry) {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entry)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data + Data("\n".utf8))
            } else {
                try (data + Data("\n".utf8)).write(to: url, options: .atomic)
            }
        } catch {
            // The daemon has no UI to complain to; the log is the whole story.
            Log.daemon.error("failed to append session history: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Every readable entry, oldest first. Tolerates garbage: a torn or
    /// hand-edited line is skipped rather than poisoning the whole log.
    func entries() -> [Entry] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return raw.split(separator: "\n").compactMap {
            try? decoder.decode(Entry.self, from: Data($0.utf8))
        }
    }

    /// True when a completion for this exact work phase already sits in the
    /// log. Guards the stop() teardown path against double-recording when it
    /// races the runner's own boundary write.
    func isAlreadyRecorded(startedAt: TimeInterval, goal: String) -> Bool {
        // Reversed: the line this races is by definition the last one appended.
        entries().reversed().contains {
            $0.startedAt == startedAt && $0.goal == goal && $0.completed
        }
    }

    // MARK: Aggregation (pure)

    struct Totals: Equatable {
        var sessions: Int
        var minutes: Int

        /// Human form: "1h 15m", "45m", "0m".
        func describe() -> String {
            let h = minutes / 60, m = minutes % 60
            switch (h, m) {
            case let (0, m): return "\(m)m"
            case let (h, 0): return "\(h)h"
            case let (h, m): return "\(h)h \(m)m"
            }
        }
    }

    /// Totals for the user's calendar day. Defined here rather than at each
    /// caller so the CLI's `focus stats` and the menu's Today line can't drift
    /// apart on what "today" starts at.
    static func todayTotals(in entries: [Entry], now: Date = Date()) -> Totals {
        totals(since: Calendar.current.startOfDay(for: now).timeIntervalSince1970, in: entries)
    }

    /// Sessions and focused minutes since `cutoff`. Partial entries count
    /// toward minutes (that focus happened) but not toward `sessions`, which
    /// means finished pomodoros only.
    static func totals(since cutoff: TimeInterval, in entries: [Entry]) -> Totals {
        let recent = entries.filter { $0.endedAt >= cutoff }
        return Totals(
            sessions: recent.filter(\.completed).count,
            minutes: recent.reduce(0) { $0 + $1.minutes }
        )
    }
}
