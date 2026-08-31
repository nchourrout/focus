import Testing
import Foundation
import Darwin
@testable import Focus

/// The identity guard on duck requests.
///
/// This is the one place Focus sends a signal whose default disposition is to
/// terminate, and it sends it automatically, twice per phase cue. A PID alone
/// stops naming the process we spawned as soon as that process exits and the OS
/// recycles the number, so a duck proves identity before it signals.
@Suite struct DuckSignalTests {

    /// How long to allow a signal to be delivered before concluding it wasn't.
    private static let deliveryWindow: TimeInterval = 0.2

    /// A live process to aim at, with its real start time. `sleep` blocks
    /// without needing a stdin pipe and dies on SIGUSR1's default disposition,
    /// which is what makes it a stand-in for the danger being guarded against.
    private func spawnVictim() throws -> (process: Process, target: LocalPlayback.Duckable) {
        let handle = try Shell.spawn(Shell.Command(path: "/bin/sleep", ["60"]))
        // The kernel publishes the start time a moment after the fork, so poll
        // for it rather than sleeping a flat guess.
        let deadline = Date().addingTimeInterval(Self.deliveryWindow)
        var startedAt: TimeInterval?
        while startedAt == nil, Date() < deadline {
            startedAt = pidStartTime(handle.pid)
            if startedAt == nil { usleep(5_000) }
        }
        let start = try #require(startedAt, "spawned process should have a start time")
        return (handle.process, LocalPlayback.Duckable(pid: handle.pid, startedAt: start))
    }

    /// True if the process is still there once a signal has had time to land.
    /// Polls, so the common case (it died) returns in milliseconds.
    private func survivesSignalWindow(_ target: LocalPlayback.Duckable) -> Bool {
        let deadline = Date().addingTimeInterval(Self.deliveryWindow)
        while Date() < deadline {
            if !isPIDAlive(target.pid) { return false }
            usleep(5_000)
        }
        return true
    }

    @Test func aMismatchedStartTimeIsNeverSignalled() throws {
        let (process, target) = try spawnVictim()
        defer { process.terminate() }

        // What a recycled PID looks like: the number is live, but it belongs to
        // a process that started at a different moment than the one we tracked.
        let recycled = LocalPlayback.Duckable(pid: target.pid, startedAt: target.startedAt - 60)
        LocalPlayback.duck(recycled, for: 0)

        #expect(survivesSignalWindow(target), "a duck reached a process Focus never spawned")
    }

    @Test func aDeadPIDIsNeverSignalled() throws {
        let (process, target) = try spawnVictim()
        process.terminate()
        process.waitUntilExit()

        // No crash, and no signal to whatever inherits the number next.
        LocalPlayback.duck(target, for: 0)
        #expect(!isPIDAlive(target.pid))
    }

    /// The other half: the guard must not be so strict that a real duck never
    /// lands. `sleep` has no SIGUSR1 handler, so delivery is visible as its death.
    @Test func aMatchingTargetIsSignalled() throws {
        let (process, target) = try spawnVictim()
        defer { if process.isRunning { process.terminate() } }

        LocalPlayback.duck(target, for: 60)

        #expect(!survivesSignalWindow(target), "the signal never arrived")
    }
}
