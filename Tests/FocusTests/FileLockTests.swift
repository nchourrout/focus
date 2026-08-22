import Testing
import Foundation
import Darwin
@testable import Focus

@Suite struct FileLockTests {

    private func makePath() throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("file-lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lock").path
    }

    @Test func bodyRunsAndItsValueComesBack() throws {
        let lock = FileLock(path: try makePath())
        #expect(try lock.withExclusiveLock { 42 } == 42)
    }

    /// flock conflicts across independent open file descriptions even within
    /// one process, so a second descriptor opened inside the held lock stands
    /// in for the competing writer.
    @Test func aHeldLockExcludesAnIndependentAcquisition() throws {
        let path = try makePath()
        let lock = FileLock(path: path)
        let excluded = try lock.withExclusiveLock { () -> Bool in
            let fd = open(path, O_RDWR | O_CREAT, 0o644)
            defer { close(fd) }
            return flock(fd, LOCK_EX | LOCK_NB) != 0
        }
        #expect(excluded, "a held exclusive lock must exclude another description")
    }

    @Test func releasedLockIsReacquirable() throws {
        let lock = FileLock(path: try makePath())
        #expect(try lock.withExclusiveLock { 1 } == 1)
        #expect(try lock.withExclusiveLock { 2 } == 2, "release on exit must not wedge later callers")
    }

    @Test func unusableLockPathStillRunsTheBody() throws {
        // A path whose parent directory doesn't exist: open fails, and the
        // documented best-effort degradation runs the body unlocked anyway —
        // losing the ability to unblock /etc/hosts would be worse than the
        // narrow race this lock closes.
        let lock = FileLock(path: "/nonexistent-focus-test-dir/lock")
        #expect(try lock.withExclusiveLock { "ran" } == "ran")
    }

    @Test func bodyThrowingPropagatesAndReleases() throws {
        let lock = FileLock(path: try makePath())
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try lock.withExclusiveLock { throw Boom() }
        }
        #expect(try lock.withExclusiveLock { 7 } == 7, "a throwing body must not leave the lock held")
    }
}
