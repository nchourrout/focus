import Testing
import Foundation
@testable import Focus

/// Settings live in one shared `UserDefaults` domain, so these run one at a time
/// and put back whatever they found.
@Suite(.serialized) struct PomodoroPlanTests {

    private func withSettings(
        work: Int, breakMinutes: Int, block: Bool, music: String,
        _ body: () throws -> Void
    ) rethrows {
        let saved = (
            work: Defaults.workMinutes, breakMinutes: Defaults.breakMinutes,
            block: Defaults.blockDuringPomodoro, music: Defaults.pomodoroMusic
        )
        defer {
            Defaults.workMinutes = saved.work
            Defaults.breakMinutes = saved.breakMinutes
            Defaults.blockDuringPomodoro = saved.block
            Defaults.pomodoroMusic = saved.music
        }
        Defaults.workMinutes = work
        Defaults.breakMinutes = breakMinutes
        Defaults.blockDuringPomodoro = block
        Defaults.pomodoroMusic = music
        try body()
    }

    @Test func settingsFillEveryGap() throws {
        // The bug this module exists to close: `focus pomodoro start` used to
        // apply a hardcoded 25/5 and ignore all of this.
        try withSettings(work: 42, breakMinutes: 7, block: false, music: "cliqhop") {
            let plan = try PomodoroPlan.fromSettings(goal: "ship it")
            #expect(plan.goal == "ship it")
            #expect(plan.workMinutes == 42)
            #expect(plan.breakMinutes == 7)
            #expect(plan.block == false)
            #expect(plan.station == .preset("cliqhop"))
        }
    }

    @Test func overridesWinOverSettings() throws {
        try withSettings(work: 42, breakMinutes: 7, block: false, music: "cliqhop") {
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

    @Test func emptyMusicSettingMeansSilence() throws {
        // With no preset set and no override, there's nothing to play unless the
        // environment names a stream.
        try withSettings(work: 25, breakMinutes: 5, block: true, music: "") {
            let plan = try PomodoroPlan.fromSettings(goal: "quiet")
            #expect(plan.station == nil || ProcessInfo.processInfo.environment["FOCUS_MUSIC_URI"] != nil)
        }
    }

    @Test func unknownPresetOverrideThrows() throws {
        try withSettings(work: 25, breakMinutes: 5, block: true, music: "") {
            #expect(throws: Station.ResolveError.self) {
                _ = try PomodoroPlan.fromSettings(goal: "x", music: "bogus")
            }
        }
    }
}
