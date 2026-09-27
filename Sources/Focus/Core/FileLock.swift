import Foundation
import Darwin

/// Exclusive advisory lock guarding read-modify-write cycles on `/etc/hosts`.
///
/// Several processes mutate that file concurrently: the daemon at every phase
/// boundary, a menu bar toggle, and whatever a user runs in a terminal. Without
/// serialization, two interleaved strip-then-write cycles can lose each other's
/// section — a block applied at a work boundary vanishing under a simultaneous
/// manual unblock. `flock` semantics fit exactly: the lock belongs to the open
/// file description, so separate processes serialize while one process can
/// still hold it across a multi-step sequence (see `SiteBlock.toggle`, which
/// must keep its isActive check and its write atomic together).
struct FileLock {
    let path: String
    /// How long to wait for a holder before giving up and running unlocked.
    /// Any stall here stalls the daemon's phase boundary, and an unblock that
    /// never comes is worse than the race the lock exists to close.
    var timeout: TimeInterval = 10

    /// Run `body` holding an exclusive lock on `path`. Best effort: if the lock
    /// file cannot be opened, or is still held after `timeout`, `body` runs
    /// unlocked anyway rather than making block/unblock unavailable. The race
    /// window it leaves open is the pre-existing behaviour; losing the ability
    /// to unblock would be worse. O_NOFOLLOW keeps root from following a
    /// planted symlink and creating a file somewhere else.
    func withExclusiveLock<T>(_ body: () throws -> T) rethrows -> T {
        let fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        guard acquire(fd) else {
            Log.daemon.error("hosts lock \(path, privacy: .public) still held after \(timeout, privacy: .public)s; proceeding unlocked")
            return try body()
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private func acquire(_ fd: Int32) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR, Date() < deadline else { return false }
            usleep(50_000)
        }
        return true
    }

}
