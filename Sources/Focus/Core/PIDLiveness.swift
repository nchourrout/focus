import Foundation
import Darwin

/// POSIX-level liveness check. Returns true if the PID names a live process we can
/// address (EPERM counts as alive; the process exists but isn't ours).
func isPIDAlive(_ pid: Int32) -> Bool {
    guard pid > 0 else { return false }
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

/// Returns the process start time (unix timestamp) for a PID, or nil if the
/// process no longer exists. Used to guard against PID recycling before we
/// SIGTERM what we think is our pomodoro daemon.
func pidStartTime(_ pid: Int32) -> TimeInterval? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
    let rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
    guard rc == size else { return nil }
    return TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
}

/// True if the PID is alive AND its start time is within ±1 second of `expectedStart`
/// (process creation timestamps are in seconds; a small tolerance covers rounding).
/// Returning false here means either the process is dead or the PID has been recycled
/// to an unrelated process.
func isOurProcess(pid: Int32, expectedStart: TimeInterval) -> Bool {
    guard isPIDAlive(pid), let actual = pidStartTime(pid) else { return false }
    return abs(actual - expectedStart) < 1.0
}
