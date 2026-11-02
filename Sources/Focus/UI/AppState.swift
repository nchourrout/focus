import Foundation
import SwiftUI

/// Menu bar app's live view of the focus state: the on-disk pomodoro state
/// file, `/etc/hosts`, and the music PID file. Emits @Published changes only
/// when values actually differ so SwiftUI doesn't re-render on every read.
///
/// Reads are event-driven. A refresh runs when one of those files changes
/// (`DirectoryWatcher`), when the current phase reaches its deadline, and on a
/// slow heartbeat for what no file event announces: a daemon or player that
/// died without cleaning up. A 1 Hz poll used to do all of it, waking the app
/// every second for the whole day to find, almost always, nothing new.
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
    /// Today's tasks, rollover applied. See `TodoList`.
    @Published private(set) var todos: [TodoList.Item] = []
    /// Today's finished work, from the history log. Re-read only when the log
    /// changes or the day does, since the log is append-only and unbounded.
    @Published private(set) var focusedToday = SessionHistory.Totals(sessions: 0, minutes: 0)
    /// What `focusedToday` was computed from: the log's modification date and
    /// the day it was read on.
    private var focusedTodayKey: FocusedTodayKey?
    // No @Published timeLeft: per-second updates would re-render every view
    // observing this, open or not. Views that need a live countdown drive
    // their own ticker (TimelineView).

    private var heartbeat: Timer?
    /// One-shot at the current phase's deadline. The daemon does write the
    /// state file at boundaries, but a break that runs out with nothing after
    /// it is a time passing, not a write, and the icon should flip on time.
    private var boundaryTimer: Timer?
    private var watcher: DirectoryWatcher?
    private var refreshInFlight = false
    /// Set when a refresh is asked for while one is running, so the change that
    /// triggered it is read after the in-flight one finishes rather than lost.
    private var refreshQueued = false
    /// Suppress notifications on the first apply: at launch we may already see
    /// a running session (the daemon survived an app restart) and we shouldn't
    /// fire "Pomodoro started" against a session that began ages ago.
    private var hasAppliedOnce = false
    /// Confirms dead-daemon sightings across two reads; see its type for why
    /// one sighting isn't enough. Lives on the main actor, which is also where
    /// the (cheap) liveness probe runs.
    private var staleDetector = StaleSessionDetector(minimumGap: 2)

    /// How often to look without being told to. Bounds how long a crashed
    /// daemon's leftover shows before recovery: two heartbeats, 10s at most.
    private static let heartbeatInterval: TimeInterval = 5

    init() {
        Task { await refresh() }
        let heartbeat = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        // Lets the system batch this wakeup with others; nothing here is that
        // time-sensitive.
        heartbeat.tolerance = 1
        RunLoop.main.add(heartbeat, forMode: .common)
        self.heartbeat = heartbeat
        // The state and PID files sit in the home directory, the task list and
        // history in Application Support. Application Support may not exist
        // yet on a fresh install, and a directory that isn't there can't be
        // watched.
        try? FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        watcher = DirectoryWatcher(files: [
            Paths.pomodoroState,
            Paths.musicPid,
            Paths.todos,
            Paths.history,
            Paths.hosts,
        ]) { [weak self] in
            Task { await self?.refresh() }
        }
    }

    deinit {
        heartbeat?.invalidate()
        boundaryTimer?.invalidate()
    }

    /// True while a work or break phase is in progress.
    var isRunning: Bool {
        pomodoro != nil && phase != .done
    }

    /// Read /etc/hosts and the pomodoro state file off the main thread so the
    /// menu bar doesn't stall on disk I/O, then publish changes back on @MainActor.
    /// Refreshes never overlap, so they can't publish out of order. One asked
    /// for mid-flight runs once the current one is done; any number of such
    /// requests collapse into that one, since it reads everything afresh.
    func refresh() async {
        guard !refreshInFlight else {
            refreshQueued = true
            return
        }
        refreshInFlight = true
        defer { refreshInFlight = false }
        repeat {
            refreshQueued = false
            let lastKey = focusedTodayKey
            let snapshot = await Task.detached {
                let key = FocusedTodayKey.current()
                return (block: SiteBlock.default.isActive,
                        state: PomodoroSession.default.current,
                        music: LocalPlayback.playing,
                        todos: TodoList.default.items(),
                        focusKey: key,
                        focused: key == lastKey
                            ? nil
                            : SessionHistory.todayTotals(in: SessionHistory.default.entries()))
            }.value
            // Kept out of `apply`: neither has any bearing on the session's
            // transitions, and the heartbeat re-reading them is also what
            // rolls both over at midnight.
            if snapshot.todos != todos { todos = snapshot.todos }
            focusedTodayKey = snapshot.focusKey
            if let focused = snapshot.focused, focused != focusedToday { focusedToday = focused }
            apply(
                blockActive: snapshot.block, state: snapshot.state,
                musicPlaying: snapshot.music.isPlaying, musicNowPlaying: snapshot.music.station
            )
            scheduleBoundaryRefresh()
        } while refreshQueued
    }

    /// Re-arm the one-shot for the running phase's deadline, or clear it when
    /// nothing is running. A paused session publishes no `pomodoro`, so it
    /// arms nothing.
    private func scheduleBoundaryRefresh() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        guard let pomodoro, phase != .done else { return }
        let timeLeft = PomodoroSession.default.phase(of: pomodoro).timeLeft
        // A little past the deadline, so the read lands on the far side of it.
        let timer = Timer(timeInterval: timeLeft + 0.2, repeats: false) { [weak self] _ in
            Task { await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
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

        // Dead-daemon recovery: a state file whose pid no longer belongs to a
        // live Focus daemon is what a crash, `kill -9`, or a reboot leaves
        // behind. Left alone it shows as a phantom countdown forever, and a
        // crash mid-work-phase keeps the /etc/hosts block on with nothing to
        // lift it. The detector demands two consecutive sightings so a normal
        // `pomodoro stop` (which clears the file itself, up to ~1s after the
        // daemon dies) never trips this path. Recovery always clears and
        // unblocks, but stay quiet when the leftover predates
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
            // Playback is a detached process of its own, so it outlives the
            // daemon that started it. Only stop it when it is still that
            // session's station, not something started separately since.
            if let music = s.music, LocalPlayback.playing.station?.uri == music {
                LocalPlayback.stop()
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
            // fires objectWillChange on every refresh during the pause, re-rendering
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

/// When the history log was last written, and today's date: `focusedToday`
/// only needs re-reading when either moves.
struct FocusedTodayKey: Equatable, Sendable {
    let modified: Date?
    let day: Date

    static func current() -> FocusedTodayKey {
        let attributes = try? FileManager.default.attributesOfItem(atPath: Paths.history.path)
        return FocusedTodayKey(
            modified: attributes?[.modificationDate] as? Date,
            day: Calendar.current.startOfDay(for: Date())
        )
    }
}

/// The status item's text: the countdown, and the goal after it when the user
/// has asked for one. Pure, so the caller decides where `showGoal` comes from.
func menuBarLabel(countdown: TimeInterval, goal: String, showGoal: Bool) -> String {
    let time = formatCountdown(countdown)
    // A goal of nothing but whitespace reaches here from `focus pomodoro start
    // "  "`, which the CLI accepts. Joining it anyway would pad the status item
    // with a separator and no content.
    let capped = showGoal ? menuBarGoal(goal) : ""
    guard !capped.isEmpty else { return time }
    return "\(time)  \(capped)"
}

/// The goal as it reads in the menu bar: whitespace collapsed to a single line
/// and capped at `limit` characters.
///
/// The cap is the point. A status item is as wide as its title, and macOS gives
/// the ones on the left away first when the bar runs out of room, so an
/// uncapped goal doesn't clip itself, it hides other apps' icons. Twenty
/// characters is about a short phrase, enough to tell two sessions apart,
/// which is all this is for.
func menuBarGoal(_ goal: String, limit: Int = 20) -> String {
    let flattened = goal.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard flattened.count > limit else { return flattened }
    // At most one space can be trailing here, the line above collapsed the runs.
    // Drop it so the ellipsis follows the word rather than a gap.
    var head = flattened.prefix(limit - 1)
    if head.hasSuffix(" ") { head = head.dropLast() }
    return String(head) + "\u{2026}"
}

/// mm:ss formatter for the status item's countdown, its one caller since the
/// goal and the countdown became a single label.
func formatCountdown(_ t: TimeInterval) -> String {
    let total = max(0, Int(t))
    return String(format: "%d:%02d", total / 60, total % 60)
}

