import Testing
import Foundation
@testable import Focus

/// `Defaults` and the environment are process-wide, so these run one at a time.
@Suite(.serialized) struct PomodoroPlanTests {

    private static let scratchSuite = "com.nchourrout.focus.tests"

    /// Run `body` against a scratch preferences domain, wiped before and after.
    /// Never touches `com.nchourrout.focus`, which is the running app's live
    /// settings on a developer's own Mac.
    private func withSettings(
        work: Int, breakMinutes: Int, block: Bool, station: Station?,
        _ body: () throws -> Void
    ) rethrows {
        let scratch = UserDefaults(suiteName: Self.scratchSuite)!
        scratch.removePersistentDomain(forName: Self.scratchSuite)
        let saved = Defaults.store
        defer {
            scratch.removePersistentDomain(forName: Self.scratchSuite)
            Defaults.store = saved
        }
        Defaults.store = scratch

        Defaults.workMinutes = work
        Defaults.breakMinutes = breakMinutes
        Defaults.blockDuringPomodoro = block
        Defaults.pomodoroStation = station
        try body()
    }

    @Test func settingsFillEveryGap() throws {
        // The bug this module exists to close: `focus pomodoro start` used to
        // apply a hardcoded 25/5 and ignore all of this.
        try withSettings(work: 42, breakMinutes: 7, block: false, station: .preset("cliqhop")) {
            let plan = try PomodoroPlan.fromSettings(goal: "ship it")
            #expect(plan.goal == "ship it")
            #expect(plan.workMinutes == 42)
            #expect(plan.breakMinutes == 7)
            #expect(plan.block == false)
            #expect(plan.station == .preset("cliqhop"))
        }
    }

    @Test func overridesWinOverSettings() throws {
        try withSettings(work: 42, breakMinutes: 7, block: false, station: .preset("cliqhop")) {
            let plan = try PomodoroPlan.fromSettings(
                goal: "ship it", workMinutes: 10, breakMinutes: 2,
                block: true, music: "dronezone"
            )
            #expect(plan.workMinutes == 10)
            #expect(plan.breakMinutes == 2)
            #expect(plan.block == true)
            #expect(plan.station == .preset("dronezone"))
        }
    }

    /// Run `body` with `FOCUS_MUSIC_URI` set to `value` (or unset for nil), then
    /// put the environment back. Serialized suite, so nothing else observes it.
    private func withMusicEnv(_ value: String?, _ body: () throws -> Void) rethrows {
        let key = "FOCUS_MUSIC_URI"
        let saved = ProcessInfo.processInfo.environment[key]
        defer {
            if let saved { setenv(key, saved, 1) } else { unsetenv(key) }
        }
        if let value { setenv(key, value, 1) } else { unsetenv(key) }
        try body()
    }

    @Test func noSettingAndNoEnvironmentMeansSilence() throws {
        try withSettings(work: 25, breakMinutes: 5, block: true, station: nil) {
            try withMusicEnv(nil) {
                let plan = try PomodoroPlan.fromSettings(goal: "quiet")
                #expect(plan.station == nil)
            }
        }
    }

    @Test func environmentIsTheLastResort() throws {
        try withSettings(work: 25, breakMinutes: 5, block: true, station: nil) {
            try withMusicEnv("https://radio.example/stream") {
                let plan = try PomodoroPlan.fromSettings(goal: "x")
                #expect(plan.station == .stream(URL(string: "https://radio.example/stream")!))
            }
        }
        // ...and the setting beats it.
        try withSettings(work: 25, breakMinutes: 5, block: true, station: .preset("cliqhop")) {
            try withMusicEnv("https://radio.example/stream") {
                let plan = try PomodoroPlan.fromSettings(goal: "x")
                #expect(plan.station == .preset("cliqhop"))
            }
        }
    }

    @Test func unusableEnvironmentCostsMusicNotTheSession() throws {
        // A local file path in FOCUS_MUSIC_URI is fine for `focus music --file`
        // but unplayable for a pomodoro. Start anyway, just without music —
        // failing here would strand the user with a Start button that does
        // nothing, since the daemon's stderr goes to /dev/null.
        try withSettings(work: 25, breakMinutes: 5, block: true, station: nil) {
            try withMusicEnv("~/brown-noise.mp3") {
                let plan = try PomodoroPlan.fromSettings(goal: "x")
                #expect(plan.station == nil)
                #expect(plan.workMinutes == 25)
            }
        }
    }

    @Test func unknownPresetOverrideThrows() throws {
        try withSettings(work: 25, breakMinutes: 5, block: true, station: nil) {
            #expect(throws: Station.ResolveError.self) {
                _ = try PomodoroPlan.fromSettings(goal: "x", music: "bogus")
            }
        }
    }
}
