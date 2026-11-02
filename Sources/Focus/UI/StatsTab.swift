import Charts
import SwiftUI

/// Focused time per day, from the same history `focus stats` reads.
struct StatsTab: View {
    @ViewState private var days = 7
    @ViewState private var entries: [SessionHistory.Entry] = []
    /// The day under the pointer, for its exact figure above the chart.
    @ViewState private var hovered: Date?

    var body: some View {
        let daily = SessionHistory.dailyTotals(days: days, in: entries)
        let window = daily.reduce(SessionHistory.Totals(sessions: 0, minutes: 0)) {
            .init(sessions: $0.sessions + $1.totals.sessions, minutes: $0.minutes + $1.totals.minutes)
        }
        let activeDays = daily.filter { $0.totals.minutes > 0 }.count

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                kpi("Today", daily.last?.totals ?? .init(sessions: 0, minutes: 0))
                kpi("Last \(days) days", window)
                kpi("Daily average", .init(
                    sessions: 0, minutes: activeDays == 0 ? 0 : window.minutes / activeDays
                ), caption: "per active day")
            }

            HStack {
                Text(hoverCaption(daily))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Picker("Range", selection: $days) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            chart(daily)
                .frame(minHeight: 260, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // Off the main thread: the log is append-only and unbounded.
            Task {
                entries = await Task.detached { SessionHistory.default.entries() }.value
            }
        }
    }

    private func kpi(_ title: String, _ totals: SessionHistory.Totals, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(totals.describe()).font(.title2.weight(.semibold)).monospacedDigit()
            Text(caption ?? "\(totals.sessions) session\(totals.sessions == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
    }

    private func chart(_ daily: [SessionHistory.DayTotal]) -> some View {
        let today = daily.last?.day
        return Chart(daily, id: \.day) { day in
            BarMark(
                x: .value("Day", day.day, unit: .day),
                y: .value("Minutes", day.totals.minutes)
            )
            .foregroundStyle(day.day == today ? Color.accentColor : Color.accentColor.opacity(0.55))
            .opacity(hovered == nil || hovered == day.day ? 1 : 0.6)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text(SessionHistory.Totals(sessions: 0, minutes: minutes).describe())
                    }
                }
            }
        }
        .chartXAxis {
            // Every day fits at 7; at 30 a label a week keeps them legible.
            AxisMarks(values: .stride(by: .day, count: days > 7 ? 7 : 1)) { _ in
                AxisValueLabel(format: days > 7 ? .dateTime.day().month(.abbreviated) : .dateTime.weekday(.abbreviated))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let x = location.x - geometry[proxy.plotAreaFrame].origin.x
                            hovered = proxy.value(atX: x, as: Date.self)
                                .map { Calendar.current.startOfDay(for: $0) }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
    }

    /// The hovered day's figure, or a hint when nothing is hovered.
    private func hoverCaption(_ daily: [SessionHistory.DayTotal]) -> String {
        guard let hovered, let day = daily.first(where: { $0.day == hovered }) else {
            return "Hover a bar for its day"
        }
        let label = day.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return "\(label): \(day.totals.summary())"
    }
}
