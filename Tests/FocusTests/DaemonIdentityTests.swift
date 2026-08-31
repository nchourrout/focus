import Testing
import Foundation
@testable import Focus

/// Which timestamp proves a pid is still this run's daemon.
///
/// The record carries two, and they answer different questions. `startedAt` is
/// when the current work phase began, and it moves at every cycle boundary.
/// `daemonStartedAt` is when the daemon process itself started, and it does not.
/// Using the first for identity meant that from session 2 onward the daemon
/// looked like a recycled pid to everything that asked: the menu bar cleared
/// live sessions as abandoned, and stop, pause and skip-break stopped signalling
/// the daemon at all, leaving it orphaned. Auto-start is on by default, so this
/// reached every run that lasted past its first break.
@Suite struct DaemonIdentityTests {

    private let session = PomodoroSession(stateURL: URL(fileURLWithPath: "/dev/null"))

    private func launched(at start: TimeInterval = 1000) -> PomodoroSession.Active {
        var active = session.firstSession(
            plan: PomodoroPlan(goal: "ship it", workMinutes: 25, breakMinutes: 5,
                               block: true, station: nil),
            cadence: PomodoroCadence(longBreakMinutes: 15, sessionsBeforeLongBreak: 4,
                                     keepCycling: true, stopAfterSet: false),
            pid: 0, at: start
        )
        // What `PomodoroDaemon.spawn` stamps once the fork returns.
        active.pid = 4242
        active.daemonStartedAt = start
        return active
    }

    // MARK: The regression

    @Test func cyclingKeepsTheDaemonStampWhileTheSessionStampMoves() {
        let first = launched()
        let second = session.nextSession(after: first, workMinutes: 25, breakMinutes: 5,
                                         at: 1000 + 30 * 60)

        #expect(second.pid == first.pid, "same daemon")
        #expect(second.startedAt != first.startedAt, "new work phase, new bracket for history")
        #expect(second.daemonStartedAt == first.daemonStartedAt, "same process, same start time")
        #expect(second.daemonIdentity == 1000, "identity still points at the fork, not the cycle")
    }

    @Test func aCycledSessionIsNotMistakenForAbandoned() {
        let fourth = (1...3).reduce(launched()) { prev, i in
            session.nextSession(after: prev, workMinutes: 25, breakMinutes: 5,
                                at: 1000 + TimeInterval(i) * 30 * 60)
        }
        // The production probe, standing in: the daemon really did start at 1000.
        let liveness: (Int32, TimeInterval) -> Bool = { $0 == 4242 && $1 == 1000 }

        #expect(!SessionStaleness.isStale(fourth, liveness: liveness),
                "a live daemon four sessions in read as a crashed one")
    }

    @Test func aCycledSessionStillDetectsARealCrash() {
        let second = session.nextSession(after: launched(), workMinutes: 25, breakMinutes: 5,
                                         at: 1000 + 30 * 60)
        #expect(SessionStaleness.isStale(second, liveness: { _, _ in false }),
                "the fix must not make every session look live")
    }

    // MARK: The rest of the lifecycle

    @Test func aSetCompleteMarkerKeepsTheStamp() {
        let done = session.completedSet(from: launched(), at: 1000 + 25 * 60)
        #expect(done.daemonStartedAt == 1000)
    }

    @Test func pausingKeepsTheStampAndResumingDropsIt() throws {
        let frozen = session.paused(launched(), at: 1500)
        #expect(frozen.daemonStartedAt == 1000, "the record is only frozen, not re-forked")

        let resumed = try #require(session.resumed(frozen, at: 2000))
        #expect(resumed.pid == 0)
        #expect(resumed.daemonStartedAt == nil,
                "a fresh daemon is coming; a stale stamp would identify the wrong process")
    }

    // MARK: On-disk compatibility

    @Test func aRecordWithoutTheStampFallsBackToStartedAt() throws {
        // What every build before this field wrote. Its identity is still
        // `startedAt`, which is what those builds compared against.
        let json = """
        {"goal":"old","pid":7,"started_at":1000,"work_end":2500,"break_end":2800,\
        "music":"","block":true}
        """
        let decoded = try JSONDecoder().decode(PomodoroSession.Active.self, from: Data(json.utf8))
        #expect(decoded.daemonStartedAt == nil)
        #expect(decoded.daemonIdentity == 1000)
    }

    @Test func theStampSurvivesADiskRoundTrip() throws {
        let data = try JSONEncoder().encode(launched())
        let decoded = try JSONDecoder().decode(PomodoroSession.Active.self, from: data)
        #expect(decoded.daemonStartedAt == 1000)

        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["daemon_started_at"] as? Double == 1000)
        #expect(obj["started_at"] as? Double == 1000, "the original key is untouched")
    }

    @Test func aRecordWithNoDaemonYetEncodesNoKey() throws {
        // firstSession runs before the fork, so there is nothing to stamp. The
        // key stays absent rather than serialising null, keeping the wire format
        // compatible with readers that predate it.
        let beforeFork = session.firstSession(
            plan: PomodoroPlan(goal: "x", workMinutes: 25, breakMinutes: 5, block: true, station: nil),
            cadence: PomodoroCadence(longBreakMinutes: 15, sessionsBeforeLongBreak: 4,
                                     keepCycling: true, stopAfterSet: false),
            pid: 0, at: 1000
        )
        let obj = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(beforeFork)) as? [String: Any]
        )
        #expect(obj["daemon_started_at"] == nil)
    }
}
