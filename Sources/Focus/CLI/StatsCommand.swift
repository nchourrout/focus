import ArgumentParser
import Foundation

/// `focus stats`: focused-time totals from the session history log.
struct StatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "show how much you've focused recently"
    )

    @Option(name: .customLong("days"),
            help: ArgumentHelp("Look-back window, today included", valueName: "DAYS"))
    var days: Int = 7

    @Flag(name: .customLong("json"), help: "Machine-readable output.")
    var json: Bool = false

    func validate() throws {
        if days <= 0 {
            throw ValidationError("--days must be a positive integer")
        }
    }

    func run() throws {
        let entries = SessionHistory.default.entries()
        let today = SessionHistory.todayTotals(in: entries)
        let daily = SessionHistory.dailyTotals(days: days, in: entries)
        let window = SessionHistory.totals(
            since: SessionHistory.windowStart(days: days).timeIntervalSince1970, in: entries
        )

        if json {
            // Fixed calendar and locale: a script parsing yyyy-MM-dd must not
            // get a Buddhist-era year because of the user's system settings.
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let payload: [String: Any] = [
                "today": ["minutes": today.minutes, "sessions": today.sessions],
                "window": ["days": days, "minutes": window.minutes, "sessions": window.sessions],
                "daily": daily.map {
                    ["date": formatter.string(from: $0.day),
                     "minutes": $0.totals.minutes, "sessions": $0.totals.sessions]
                },
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("focus: today \(today.summary())")
        print("focus: last \(days)d \(window.summary())")
        for line in Self.bars(daily) { print(line) }
    }

    /// One line per day, bar scaled to the busiest day in the window.
    static func bars(_ daily: [SessionHistory.DayTotal], width: Int = 20) -> [String] {
        let peak = daily.map(\.totals.minutes).max() ?? 0
        let formatter = DateFormatter()
        // Weekday names repeat past a week; add the date once they would.
        formatter.setLocalizedDateFormatFromTemplate(daily.count > 7 ? "EEE d MMM" : "EEE")
        let labels = daily.map { formatter.string(from: $0.day) }
        let labelWidth = labels.map(\.count).max() ?? 0
        return zip(daily, labels).map { day, label in
            let filled = peak == 0 ? 0 : Int((Double(day.totals.minutes) / Double(peak) * Double(width)).rounded())
            let bar = String(repeating: "█", count: filled)
                + String(repeating: " ", count: width - filled)
            let pad = String(repeating: " ", count: labelWidth - label.count)
            return "  \(label)\(pad) \(bar) \(day.totals.describe())"
        }
    }
}
