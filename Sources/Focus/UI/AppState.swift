import Foundation
import SwiftUI

/// Menu bar app's live view of the focus state. Polls the on-disk state file and
/// `/etc/hosts` once a second. Emits @Published changes only when values actually
/// differ so SwiftUI doesn't re-render every tick unnecessarily.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var pomodoro: PomodoroSession.Active?
    @Published private(set) var phase: PomodoroSession.Phase = .done
    @Published private(set) var blockActive: Bool = false
    @Published private(set) var musicPlaying: Bool = false
    // No @Published timeLeft: per-second updates would also re-render the menu
    // dropdown via @ObservedObject, which resets AppKit's hover selection.
    // Views that need a live countdown drive their own ticker (TimelineView).

    private var timer: Timer?
    private var refreshInFlight = false
    /// Suppress notifications on the first apply: at launch we may already see
    /// a running session (the daemon survived an app restart) and we shouldn't
    /// fire "Pomodoro started" against a session that began ages ago.
    private var hasAppliedOnce = false

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
            (block: SiteBlock.default.isActive,
             state: PomodoroSession.default.current,
             music: LocalPlayback.isPlaying)
        }.value
        apply(blockActive: snapshot.block, state: snapshot.state, musicPlaying: snapshot.music)
    }

    private func apply(blockActive newBlock: Bool, state: PomodoroSession.Active?, musicPlaying newMusic: Bool) {
        if newBlock != blockActive { blockActive = newBlock }
        if newMusic != musicPlaying { musicPlaying = newMusic }

        let prevPomodoro = pomodoro
        let prevPhase = phase

        let newPhase: PomodoroSession.Phase
        if let s = state {
            // pomodoro/phase only republish on discrete changes (start/stop,
            // work→break, break→done, auto-start loop iterations) — at most a
            // handful of times per session. workEnd is part of the comparison
            // because auto-start rewrites the state file with new deadlines
            // but the same pid/goal.
            newPhase = PomodoroSession.default.phase(of: s).phase
            if pomodoro?.pid != s.pid
                || pomodoro?.goal != s.goal
                || pomodoro?.workEnd != s.workEnd { pomodoro = s }
        } else {
            if pomodoro != nil { pomodoro = nil }
            newPhase = .done
        }
        if newPhase != phase { phase = newPhase }

        defer { hasAppliedOnce = true }
        guard hasAppliedOnce else { return }
        emitTransitionNotification(
            from: (prevPomodoro, prevPhase),
            to: (pomodoro, phase)
        )
    }

    /// Detect work/break boundaries and post a notification through the UI
    /// process so the Focus app icon appears on the banner. Goes through here
    /// rather than from the daemon because the daemon has no NSApplication
    /// and `osascript display notification` always attributes to Script Editor.
    private func emitTransitionNotification(
        from prev: (PomodoroSession.Active?, PomodoroSession.Phase),
        to curr: (PomodoroSession.Active?, PomodoroSession.Phase)
    ) {
        let (prevPomo, prevPhase) = prev
        let (currPomo, currPhase) = curr

        // Start: nothing → work.
        if prevPomo == nil, let s = currPomo, currPhase == .work {
            LocalNotifications.post(title: "Pomodoro started", body: s.goal, sound: nil)
            Sounds.play(.sessionStart)
            return
        }
        // Auto-start loop: break → fresh work (workEnd advanced).
        if prevPhase == .break, currPhase == .work, let s = currPomo {
            LocalNotifications.post(
                title: "Session \(s.sessionNumber)", body: s.goal, sound: nil
            )
            Sounds.play(.sessionStart)
            return
        }
        // Work → break. Every Nth session earns the longer break, decided when the
        // session was scheduled (Active.isLongBreak), so the label matches the
        // break that was actually planned.
        if prevPhase == .work, currPhase == .break, let s = currPomo {
            LocalNotifications.post(
                title: s.isLongBreak ? "Long break" : "Pomodoro complete",
                body: s.isLongBreak
                    ? "\(s.sessionNumber) sessions done — take a longer break."
                    : "Finished: \(s.goal). Break time.",
                sound: nil
            )
            Sounds.play(.breakStart)
            return
        }
        // End of session: break → done (or daemon cleared the file).
        if prevPhase == .break, currPhase == .done {
            LocalNotifications.post(
                title: "Break over",
                body: "Ready for another session?",
                sound: nil
            )
            Sounds.play(.sessionEnd)
            return
        }
    }
}

/// mm:ss formatter, used by both the menu bar label and the dropdown.
func formatCountdown(_ t: TimeInterval) -> String {
    let total = max(0, Int(t))
    return String(format: "%d:%02d", total / 60, total % 60)
}
