import Testing
import Foundation
import Darwin
@testable import Focus

/// The identity guard on duck requests.
///
/// This is the one place Focus sends a signal whose default disposition is to
/// terminate, and it sends it automatically, twice per phase cue. A PID alone
/// stops naming the process we spawned as soon as that process exits and the OS
/// recycles the number, so `setDucked` proves identity before it signals.
@Suite struct DuckSignalTests {

    /// A live process to aim at, with its real start time. `cat` with no
    /// redirection blocks on stdin forever and dies on SIGUSR1's default
    /// disposition, which is what makes it a usable stand-in for the danger.
    private func spawnVictim() throws -> (process: Process, target: LocalPlayback.Duckable) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Give the kernel a moment to publish the process before reading its
        // start time, the same way `LocalPlayback.play` reads it after spawning.
        usleep(200_000)
        let pid = process.processIdentifier
        let startedAt = try #require(pidStartTime(pid), "spawned process should have a start time")
        return (process, LocalPlayback.Duckable(pid: pid, startedAt: startedAt))
    }

    private func isAlive(_ target: LocalPlayback.Duckable) -> Bool {
        usleep(200_000)
        return isPIDAlive(target.pid)
    }

    @Test func aMismatchedStartTimeIsNeverSignalled() throws {
        let (process, target) = try spawnVictim()
        defer { process.terminate() }

        // What a recycled PID looks like: the number is live, but it belongs to
        // a process that started at a different moment than the one we tracked.
        let recycled = LocalPlayback.Duckable(pid: target.pid, startedAt: target.startedAt - 60)
        LocalPlayback.setDucked(true, on: recycled)

        #expect(isAlive(target), "a duck request reached a process Focus never spawned")
    }

    @Test func aDeadPIDIsNeverSignalled() throws {
        let (process, target) = try spawnVictim()
        process.terminate()
        process.waitUntilExit()

        // No crash, no signal to whatever inherits the number next.
        LocalPlayback.setDucked(false, on: target)
        #expect(!isPIDAlive(target.pid))
    }

    /// The other half: the guard must not be so strict that a real duck never
    /// lands. `cat` has no SIGUSR1 handler, so delivery is visible as its death.
    @Test func aMatchingTargetIsSignalled() throws {
        let (process, target) = try spawnVictim()
        defer { if process.isRunning { process.terminate() } }

        LocalPlayback.setDucked(true, on: target)

        #expect(!isAlive(target), "the signal never arrived")
    }
}
