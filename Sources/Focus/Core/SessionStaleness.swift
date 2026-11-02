import Foundation

/// Whether an on-disk pomodoro record still belongs to a living daemon.
///
/// The state file outlives its writer: a daemon killed by a crash, OOM, or a
/// reboot leaves every field intact while the sites it blackholed stay blocked.
/// Callers use staleness to tell that leftover apart from a live session the
/// menu bar can merely observe.
enum SessionStaleness {
    /// True when the record cannot belong to a live Focus daemon. A missing or
    /// zero pid counts as stale: `PomodoroDaemon.launch` writes the real pid
    /// immediately after spawning, so pid 0 never describes a running session.
    /// Paused sessions are the one exception — their daemon is gone by design,
    /// waiting for `pomodoro resume` — so they read as owned, not abandoned.
    /// Liveness is injected so the decision is testable without a process
    /// table; production passes `isOurProcess(pid:expectedStart:)`, whose start-
    /// time comparison is what rules out PID recycling. It compares against
    /// `daemonIdentity`, not `startedAt`: see that property for why.
    static func isStale(
        _ active: PomodoroSession.Active,
        liveness: (_ pid: Int32, _ startedAt: TimeInterval) -> Bool = {
            isOurProcess(pid: $0, expectedStart: $1)
        }
    ) -> Bool {
        if active.pausedAt != nil { return false }
        guard active.pid > 0 else { return true }
        return !liveness(active.pid, active.daemonIdentity)
    }
}

/// Confirms staleness across two observations at least `minimumGap` apart, so
/// recovery only fires on a genuinely abandoned session.
///
/// One sighting is not enough: a normal `pomodoro stop` SIGTERMs the daemon and
/// clears the state file itself, leaving a dead-pid-but-present record visible
/// for up to the second `stop()` waits before cleaning up. Acting on that first
/// sighting would race the stop's own cleanup and post a spurious "session
/// interrupted" banner for a stop the user asked for.
///
/// The gap is measured in time, not in reads, because the menu bar refreshes on
/// file events as well as on its heartbeat: two reads can land milliseconds
/// apart, well inside the window a stop needs.
struct StaleSessionDetector {
    private var pendingStalePID: Int32?
    private var firstSighting: TimeInterval = 0
    let minimumGap: TimeInterval

    init(minimumGap: TimeInterval = 0) {
        self.minimumGap = minimumGap
    }

    /// Feed every observed state-file read (nil included). Returns true once the
    /// same stale pid has been seen again at least `minimumGap` after it was
    /// first seen; any healthy read or absent file resets the count.
    mutating func confirmStale(
        _ active: PomodoroSession.Active?,
        now: TimeInterval = Date().timeIntervalSince1970,
        liveness: (_ pid: Int32, _ startedAt: TimeInterval) -> Bool = {
            isOurProcess(pid: $0, expectedStart: $1)
        }
    ) -> Bool {
        guard let active, SessionStaleness.isStale(active, liveness: liveness) else {
            pendingStalePID = nil
            return false
        }
        guard pendingStalePID == active.pid else {
            pendingStalePID = active.pid
            firstSighting = now
            return false
        }
        return now - firstSighting >= minimumGap
    }
}
