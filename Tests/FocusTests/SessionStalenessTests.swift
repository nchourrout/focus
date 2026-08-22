import Testing
import Foundation
@testable import Focus

@Suite struct SessionStalenessTests {

    private func makeActive(
        pid: Int32 = 4242, startedAt: TimeInterval = 1000, block: Bool = true
    ) -> PomodoroSession.Active {
        PomodoroSession.Active(
            goal: "write tests", pid: pid, startedAt: startedAt,
            workEnd: 1000 + 25 * 60, breakEnd: 1000 + 30 * 60,
            music: nil, block: block
        )
    }

    /// The production liveness probe stands in: alive iff pid matches.
    private static func liveWhenPIDMatches(pid: Int32, expectedStart: TimeInterval) -> Bool {
        pid == 4242 && expectedStart == 1000
    }

    // MARK: SessionStaleness.isStale

    @Test func liveDaemonIsNotStale() {
        #expect(!SessionStaleness.isStale(makeActive(), liveness: Self.liveWhenPIDMatches))
    }

    @Test func deadOrRecycledPidIsStale() {
        #expect(SessionStaleness.isStale(makeActive(), liveness: { _, _ in false }))
    }

    @Test func mismatchedStartTimeIsStale() {
        // PID recycling: same pid, different process (born at another time).
        #expect(SessionStaleness.isStale(makeActive()) { _, start in start == 999 })
    }

    @Test func zeroPidIsDefensivelyStale() {
        #expect(SessionStaleness.isStale(makeActive(pid: 0), liveness: { _, _ in true }))
        #expect(SessionStaleness.isStale(makeActive(pid: -1), liveness: { _, _ in true }))
    }

    @Test func pausedSessionIsNeverStale() {
        // The daemon of a paused session is gone by design; the record is
        // owned, waiting for `pomodoro resume`. Liveness must be irrelevant.
        var frozen = makeActive()
        frozen.pausedAt = 1234
        #expect(!SessionStaleness.isStale(frozen, liveness: { _, _ in false }))
        #expect(!SessionStaleness.isStale(frozen, liveness: { _, _ in true }))
    }

    @Test func stalenessIsIndependentOfBlockFlag() {
        #expect(!SessionStaleness.isStale(makeActive(block: false), liveness: Self.liveWhenPIDMatches))
        #expect(SessionStaleness.isStale(makeActive(block: false), liveness: { _, _ in false }))
    }

    // MARK: StaleSessionDetector (two-tick confirmation)

    /// Feeds with the recorded process reported GONE — the stale scenario.
    private func feedDead(_ detector: inout StaleSessionDetector,
                          _ active: PomodoroSession.Active?) -> Bool {
        detector.confirmStale(active, liveness: { _, _ in false })
    }

    /// Feeds with the process reported alive again.
    private func feedLive(_ detector: inout StaleSessionDetector,
                          _ active: PomodoroSession.Active?) -> Bool {
        detector.confirmStale(active, liveness: Self.liveWhenPIDMatches)
    }

    @Test func oneSightingDoesNotConfirm() {
        var detector = StaleSessionDetector()
        #expect(!feedDead(&detector, makeActive()))
    }

    @Test func twoConsecutiveSightingsConfirm() {
        var detector = StaleSessionDetector()
        #expect(!feedDead(&detector, makeActive()))
        #expect(feedDead(&detector, makeActive()))
    }

    @Test func aThirdSightingStillConfirms() {
        var detector = StaleSessionDetector()
        _ = feedDead(&detector, makeActive())
        #expect(feedDead(&detector, makeActive()))
        #expect(feedDead(&detector, makeActive()))
    }

    @Test func healthyReadResetsTheCount() {
        var detector = StaleSessionDetector()
        #expect(!feedDead(&detector, makeActive()))
        #expect(!feedLive(&detector, makeActive()), "alive again; the count must drop")
        #expect(!feedDead(&detector, makeActive()), "needs two fresh dead sightings")
    }

    @Test func absentFileResetsTheCount() {
        var detector = StaleSessionDetector()
        #expect(!feedDead(&detector, makeActive()))
        #expect(!feedDead(&detector, nil))
        #expect(!feedDead(&detector, makeActive()), "needs two fresh sightings after reset")
    }

    @Test func aDifferentPidRestartsTheCount() {
        var detector = StaleSessionDetector()
        #expect(!feedDead(&detector, makeActive(pid: 4242)))
        #expect(!feedDead(&detector, makeActive(pid: 5151)))
        #expect(!feedDead(&detector, makeActive(pid: 4242)))
        #expect(feedDead(&detector, makeActive(pid: 4242)))
    }
}
