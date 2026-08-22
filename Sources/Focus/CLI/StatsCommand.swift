import ArgumentParser
import Foundation

/// `focus stats`: focused-time totals from the session history log.
struct StatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "show how much you've focused recently"
    )

    @Option(name: .customLong("days"),
            help: ArgumentHelp("Look-back window for the range line", valueName: "DAYS"))
    var days: Int = 7

    func validate() throws {
        if days <= 0 {
            throw ValidationError("--days must be a positive integer")
        }
    }

    func run() {
        let entries = SessionHistory.default.entries()
        let now = Date().timeIntervalSince1970
        let dayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

        let today = SessionHistory.totals(since: dayStart, in: entries)
        let window = SessionHistory.totals(since: now - Double(days) * 86_400, in: entries)

        print("focus: today \(today.describe()) across \(today.sessions) sessions")
        print("focus: last \(days)d \(window.describe()) across \(window.sessions) sessions")
    }
}
