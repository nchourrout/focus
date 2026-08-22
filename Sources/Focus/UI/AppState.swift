import Foundation
import SwiftUI

/// Menu bar app's live view of the focus state. Polls the on-disk state file and
/// `/etc/hosts` once a second. Emits @Published changes only when values actually
/// differ so SwiftUI doesn't re-render every tick unnecessarily.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var pomodoro: PomodoroSession.Active?
    @Published private(set) var phase: PomodoroSession.Phase = .done
    /// The record while its session is paused. Nil otherwise; a paused session
    /// publishes no `pomodoro`, so `isRunning` reads false and the UI offers
    /// Resume instead of Stop.
    @Published private(set) var pausedSession: PomodoroSession.Active?
    @Published private(set) var blockActive: Bool = false
    @Published private(set) var musicPlaying: Bool = false
    /// What's playing. Nil while stopped, or when an older build wrote a
    /// label-less PID file.
    @Published private(set) var musicNowPlaying: Station?
    // No @Published timeLeft: per-second updates would also re-render the menu
    // dropdown via @ObservedObject, which resets AppKit's hover selection.
    // Views that need a live countdown drive their own ticker (TimelineView).

    private var timer: Timer?
    private var refreshInFlight = false
    /// Suppress notifications on the first apply: at launch we may already see
    /// a running session (the daemon survived an app restart) and we shouldn't
    /// fire "Pomodoro started" against a session that began ages ago.
    private var hasAppliedOnce = false
    /// Confirms dead-daemon sightings across consecutive ticks; see its type
    /// for why one sighting isn't enough. Lives on the main actor, which is
    /// also where the (cheap) liveness probe runs.
    private var staleDetector = StaleSessionDetector()

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
             music: LocalPlayback.playing)
        }.value
        apply(
            blockActive: snapshot.block, state: snapshot.state,
            musicPlaying: snapshot.music.isPlaying, musicNowPlaying: snapshot.music.station
        )
    }

    private func apply(
        blockActive newBlock: Bool, state: PomodoroSession.Active?,
        musicPlaying newMusic: Bool, musicNowPlaying newNowPlaying: Station?
    ) {
        // Capture before the defer flips it, so every exit path shares one rule:
        // the first apply suppresses notifications (see the marker branch and the
        // transition emitter below).
        let wasApplied = hasAppliedOnce
        defer { hasAppliedOnce = true }

        if newBlock != blockActive { blockActive = newBlock }
        if newMusic != musicPlaying { musicPlaying = newMusic }
        if newNowPlaying != musicNowPlaying { musicNowPlaying = newNowPlaying }

        // Set-complete marker: the daemon ended a "stop after each set" run (it
        // already unblocked and stopped music). Post the actionable "start
        // another set" notification, then clear the file so we settle to idle.
        // Skip the notification for a marker first seen at launch (the set ended
        // while the app was closed) — but still clear it. Clearing here is the
        // one place AppState writes the state file; safe because the daemon has
        // exited, so there's no concurrent writer.
        if let s = state, s.setComplete {
            if wasApplied {
                LocalNotifications.postSetComplete(goal: s.goal)
                Sounds.play(.sessionEnd)
            }
            PomodoroSession.default.clear()
            pomodoro = nil
            phase = .done
            return
        }

        // Dead-daemon recovery: a state file whose pid no longer belongs to a
        // live Focus daemon is what a crash, `kill -9`, or a reboot leaves
        // behind. Left alone it shows as a phantom countdown forever, and a
        // crash mid-work-phase keeps the /etc/hosts block on with nothing to
        // lift it. The detector demands two consecutive sightings so a normal
        // `pomodoro stop` (which clears the file itself, up to ~1s after the
        // daemon dies) never trips this path. Recovery mirrors set-complete:
        // always clear and unblock, but stay quiet when the leftover predates
        // this launch — that session ended while the app was closed.
        var state = state
        // `confirmStale` takes the optional itself and clears its own counter on
        // any absent or healthy read, so this is the one place a tick feeds it.
        if staleDetector.confirmStale(state), let s = state {
            PomodoroSession.default.clear()
            // Lift the block only when this run owned one AND the markers are
            // still in /etc/hosts: a manual unblock during the gap makes the
            // sudo call pointless, and --no-block sessions never had one.
            if s.block && newBlock {
                Actions.spawnSudo(["unblock"])
            }
            if wasApplied {
                LocalNotifications.post(
                    title: "Session interrupted",
                    body: "Focus cleaned up a pomodoro that ended unexpectedly.",
                    sound: nil
                )
                Sounds.play(.sessionEnd)
            }
            Log.actions.notice(
                "recovered stale session (pid \(s.pid), goal \(s.goal, privacy: .public))"
            )
            state = nil
        }

        let wasPaused = pausedSession != nil

        // Paused session: the daemon is gone by design, so there's nothing to
        // probe or recover. Publish the record for the Resume affordances and
        // settle everything else to idle until `resume` spawns a fresh daemon.
        if let s = state, s.pausedAt != nil {
            if pomodoro != nil { pomodoro = nil }
            // Guarded like every other publish here: an unguarded assignment
            // fires objectWillChange on all 1 Hz ticks of the pause, re-rendering
            // the menu bar for the whole time the session sits frozen.
            if phase != .done { phase = .done }
            if pausedSession != s { pausedSession = s }
            return
        }
        if pausedSession != nil {
            // Resumed (or discarded): drop the marker before the normal path
            // republishes a running session.
            pausedSession = nil
        }

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

        guard wasApplied else { return }
        // A resume looks exactly like a fresh start to the transition detector;
        // the user initiated it, so no banner is wanted either way.
        guard !wasPaused else { return }
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
