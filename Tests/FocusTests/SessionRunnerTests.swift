import Testing
import Foundation
@testable import Focus

/// Records what the run loop did to the outside world, and drives a virtual
/// clock so a four-session set takes microseconds instead of two hours.
private final class FakeEffects: SessionEffects {
    enum Event: Equatable {
        case applyBlock
        case removeBlock
        case startMusic(Station)
        case stopMusic
        case slept(until: TimeInterval)
    }

    var clock: TimeInterval
    var cadence: PomodoroCadence
    private(set) var events: [Event] = []
    /// Runs after each sleep with the number of sleeps so far. Lets a test change
    /// the cadence mid-run, or pull the state file out from under the loop.
    var onSleep: (Int) -> Void = { _ in }

    init(clock: TimeInterval, cadence: PomodoroCadence) {
        self.clock = clock
        self.cadence = cadence
    }

    var now: TimeInterval { clock }

    /// Sleeping is the only thing that advances the clock.
    func sleep(until deadline: TimeInterval) {
        if deadline > clock { clock = deadline }
        events.append(.slept(until: deadline))
        onSleep(sleeps)
    }

    func applyBlock() { events.append(.applyBlock) }
    func removeBlock() { events.append(.removeBlock) }
    func startMusic(_ station: Station) { events.append(.startMusic(station)) }
    func stopMusic() { events.append(.stopMusic) }

    var sleepDeadlines: [TimeInterval] {
        events.compactMap { if case .slept(let d) = $0 { return d } else { return nil } }
    }
    var sleeps: Int { sleepDeadlines.count }
    var musicStarts: Int {
        events.filter { if case .startMusic = $0 { return true } else { return false } }.count
    }
}

@Suite struct SessionRunnerTests {

    private static let start: TimeInterval = 1000
    private static let workEnd: TimeInterval = 1000 + 25 * 60
    private static let breakEnd: TimeInterval = 1000 + 30 * 60

    private func makeCadence(
        keepCycling: Bool = false, stopAfterSet: Bool = false,
        sessionsBeforeLongBreak: Int = 4, longBreakMinutes: Int = 15
    ) -> PomodoroCadence {
        PomodoroCadence(
            longBreakMinutes: longBreakMinutes,
            sessionsBeforeLongBreak: sessionsBeforeLongBreak,
            keepCycling: keepCycling,
            stopAfterSet: stopAfterSet
        )
    }

    private func makePlan(block: Bool = true, station: Station? = .preset("dronezone")) -> PomodoroPlan {
        PomodoroPlan(goal: "write tests", workMinutes: 25, breakMinutes: 5, block: block, station: station)
    }

    /// A session sandboxed to a fresh tmp state file, seeded the way
    /// `PomodoroDaemon.launch` seeds it before forking the daemon.
    private func makeSession(sessionNumber: Int = 1) throws -> PomodoroSession {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("session-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let session = PomodoroSession(stateURL: dir.appendingPathComponent("state.json"))
        try session.save(PomodoroSession.Active(
            goal: "write tests", pid: 4242, startedAt: Self.start,
            workEnd: Self.workEnd, breakEnd: Self.breakEnd,
            music: MusicPresets.uri(for: "dronezone"), block: true,
            sessionNumber: sessionNumber, isLongBreak: false
        ))
        return session
    }

    private func run(
        plan: PomodoroPlan, session: PomodoroSession, effects: FakeEffects
    ) {
        SessionRunner(plan: plan, session: session, effects: effects)
            .run(workEnd: Self.workEnd, breakEnd: Self.breakEnd)
    }

    // MARK: One session

    @Test func singleSessionBlocksWorksBreaksAndTearsDown() throws {
        let session = try makeSession()
        let effects = FakeEffects(clock: Self.start, cadence: makeCadence(keepCycling: false))

        run(plan: makePlan(), session: session, effects: effects)

        #expect(effects.events == [
            .applyBlock,
            .startMusic(.preset("dronezone")),
            .slept(until: Self.workEnd),
            // The block lifts for the break so the user can browse freely.
            .removeBlock,
            .slept(until: Self.breakEnd),
            // Teardown unblocks again as the documented safety net.
            .removeBlock,
            .stopMusic,
        ])
        #expect(session.current == nil, "teardown clears the state file")
    }

    @Test func aSessionThatNeverBlockedNeverTouchesTheBlock() throws {
        let session = try makeSession()
        let effects = FakeEffects(clock: Self.start, cadence: makeCadence(keepCycling: false))

        run(plan: makePlan(block: false), session: session, effects: effects)

        #expect(!effects.events.contains(.applyBlock))
        #expect(!effects.events.contains(.removeBlock), "no sudo call for a session that never blocked")
    }

    @Test func silentSessionStartsNoMusicButStillStopsIt() throws {
        let session = try makeSession()
        let effects = FakeEffects(clock: Self.start, cadence: makeCadence(keepCycling: false))

        run(plan: makePlan(station: nil), session: session, effects: effects)

        #expect(effects.musicStarts == 0)
        // Teardown still stops playback: something else may have started it.
        #expect(effects.events.contains(.stopMusic))
    }

    // MARK: Cycling

    @Test func cyclingRollsDeadlinesAndRestoresTheBlock() throws {
        let session = try makeSession()
        let effects = FakeEffects(clock: Self.start, cadence: makeCadence(keepCycling: true))
        var secondSession: PomodoroSession.Active?
        effects.onSleep = { count in
            // Capture session 2 before teardown clears the file, then end the run.
            if count == 3 { secondSession = session.current }
            if count == 4 { effects.cadence.keepCycling = false }
        }

        run(plan: makePlan(), session: session, effects: effects)

        #expect(secondSession?.sessionNumber == 2)
        #expect(secondSession?.goal == "write tests", "the goal carries over")
        #expect(secondSession?.pid == 4242, "same daemon process, same pid")
        // Session 2's work phase starts when session 1's break ended.
        #expect(secondSession?.workEnd == Self.breakEnd + 25 * 60)
        #expect(effects.sleepDeadlines == [
            Self.workEnd, Self.breakEnd,
            Self.breakEnd + 25 * 60, Self.breakEnd + 30 * 60,
        ])
        // Block lifted for each break, reapplied for each work phase.
        #expect(effects.events.filter { $0 == .applyBlock }.count == 2)
        #expect(effects.events.contains(.startMusic(.preset("dronezone"))))
        #expect(effects.musicStarts == 1, "music carries over rather than restarting each session")
    }

    @Test func longBreakLandsOnEveryNthSession() throws {
        let session = try makeSession(sessionNumber: 3)
        let effects = FakeEffects(
            clock: Self.start,
            cadence: makeCadence(keepCycling: true, sessionsBeforeLongBreak: 4, longBreakMinutes: 15)
        )
        var fourth: PomodoroSession.Active?
        effects.onSleep = { count in
            if count == 3 { fourth = session.current }
            if count == 4 { effects.cadence.keepCycling = false }
        }

        run(plan: makePlan(), session: session, effects: effects)

        #expect(fourth?.sessionNumber == 4)
        #expect(fourth?.isLongBreak == true)
        #expect(
            (fourth?.breakEnd ?? 0) - (fourth?.workEnd ?? 0) == 15 * 60,
            "the 4th session earns the long break, not the short one"
        )
    }

    @Test func cadenceIsRereadSoSettingsChangesLandAtTheNextBoundary() throws {
        let session = try makeSession()
        let effects = FakeEffects(clock: Self.start, cadence: makeCadence(keepCycling: true))
        // Turn cycling off during the first break: the run should end there
        // rather than starting a second session.
        effects.onSleep = { count in
            if count == 2 { effects.cadence.keepCycling = false }
        }

        run(plan: makePlan(), session: session, effects: effects)

        #expect(effects.sleeps == 2, "no second work phase")
        #expect(session.current == nil)
    }

    // MARK: Set boundary

    @Test func stopAfterSetEndsAtTheBoundaryWithoutAFinalBreak() throws {
        let session = try makeSession(sessionNumber: 4)
        let effects = FakeEffects(
            clock: Self.start,
            cadence: makeCadence(keepCycling: true, stopAfterSet: true, sessionsBeforeLongBreak: 4)
        )

        run(plan: makePlan(), session: session, effects: effects)

        #expect(effects.sleeps == 1, "the set ends after the work phase, skipping the final break")
        #expect(effects.events == [
            .applyBlock,
            .startMusic(.preset("dronezone")),
            .slept(until: Self.workEnd),
            .removeBlock,
            .stopMusic,
        ])
        // A terminal marker is left for the menu bar app to notice.
        let marker = try #require(session.current)
        #expect(marker.setComplete)
        #expect(marker.sessionNumber == 4)
        #expect(marker.workEnd == Self.workEnd, "deadlines pulled back so the phase reads .done")
        #expect(marker.breakEnd == Self.workEnd)
    }

    @Test func stopAfterSetIgnoredMidSet() throws {
        let session = try makeSession(sessionNumber: 2)
        let effects = FakeEffects(
            clock: Self.start,
            cadence: makeCadence(keepCycling: true, stopAfterSet: true, sessionsBeforeLongBreak: 4)
        )
        effects.onSleep = { count in
            if count == 2 { effects.cadence.keepCycling = false }
        }

        run(plan: makePlan(), session: session, effects: effects)

        #expect(effects.sleeps == 2, "session 2 of 4 takes its break as usual")
        #expect(session.current?.setComplete != true)
    }

    @Test func stopAfterSetNeedsCyclingOn() throws {
        let session = try makeSession(sessionNumber: 4)
        let effects = FakeEffects(
            clock: Self.start,
            cadence: makeCadence(keepCycling: false, stopAfterSet: true, sessionsBeforeLongBreak: 4)
        )

        run(plan: makePlan(), session: session, effects: effects)

        #expect(effects.sleeps == 2, "without cycling there is no set to stop after")
        #expect(session.current == nil)
    }

    // MARK: Races

    @Test func bailsOutWhenTheStateFileVanishesMidLoop() throws {
        let session = try makeSession()
        let effects = FakeEffects(clock: Self.start, cadence: makeCadence(keepCycling: true))
        // `pomodoro stop` racing with the break→work transition.
        effects.onSleep = { count in
            if count == 2 { session.clear() }
        }

        run(plan: makePlan(), session: session, effects: effects)

        #expect(effects.sleeps == 2, "the run ends instead of starting a phantom session")
        #expect(session.current == nil, "no phantom state written back")
    }
}
