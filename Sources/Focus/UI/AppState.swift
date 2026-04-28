import Foundation
import SwiftUI

/// Menu bar app's live view of the focus state. Polls the on-disk state file and
/// `/etc/hosts` once a second. Emits @Published changes only when values actually
/// differ so SwiftUI doesn't re-render every tick unnecessarily.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var pomodoro: PomodoroState?
    @Published private(set) var phase: PomodoroState.Phase = .done
    @Published private(set) var timeLeft: TimeInterval = 0
    @Published private(set) var blockActive: Bool = false

    private var timer: Timer?
    private var refreshInFlight = false

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    /// True while a work or break phase is in progress.
    var isRunning: Bool {
        pomodoro != nil && phase != .done
    }

    /// Read /etc/hosts and the pomodoro state file off the main thread so the
    /// menu bar doesn't stall on disk I/O, then publish changes back on @MainActor.
    /// If the previous tick is still draining (slow disk, suspended laptop), skip
    /// this one rather than letting refreshes accumulate and publish out of order.
    func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        let snapshot = await Task.detached {
            (block: HostsFile.isActive(), state: PomodoroState.current)
        }.value
        apply(blockActive: snapshot.block, state: snapshot.state)
    }

    private func apply(blockActive newBlock: Bool, state: PomodoroState?) {
        if newBlock != blockActive { blockActive = newBlock }

        guard let s = state else {
            if pomodoro != nil { pomodoro = nil }
            if phase != .done { phase = .done }
            if timeLeft != 0 { timeLeft = 0 }
            return
        }

        let (newPhase, newTimeLeft) = s.phase()
        if pomodoro?.pid != s.pid || pomodoro?.goal != s.goal { pomodoro = s }
        if newPhase != phase { phase = newPhase }
        // Seconds granularity: skip re-render if the displayed time hasn't changed.
        if Int(newTimeLeft) != Int(timeLeft) { timeLeft = newTimeLeft }
    }
}

/// mm:ss formatter, used by both the menu bar label and the dropdown.
func formatCountdown(_ t: TimeInterval) -> String {
    let total = max(0, Int(t))
    return String(format: "%d:%02d", total / 60, total % 60)
}
