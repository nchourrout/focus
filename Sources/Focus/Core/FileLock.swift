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

    /// Run `body` holding an exclusive lock on `path`. Best effort: if the lock
    /// file cannot be opened or flocked (unwritable /tmp is about the only way,
    /// and every mutator runs as root), `body` runs unlocked anyway rather than
    /// making block/unblock unavailable. The race window it leaves open is the
    /// pre-existing behaviour; losing the ability to unblock would be worse.
    func withExclusiveLock<T>(_ body: () throws -> T) rethrows -> T {
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        if flock(fd, LOCK_EX) != 0 { return try body() }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    /// Non-blocking variant for tests: nil means someone else held the lock.
    /// Same best-effort degradation when the lock file itself is unusable.
    func tryExclusiveLock<T>(_ body: () throws -> T) rethrows -> T? {
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return try body() }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return nil }
        return try body()
    }
}
