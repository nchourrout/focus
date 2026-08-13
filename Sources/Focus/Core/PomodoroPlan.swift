import Foundation

/// Everything fixed for the duration of one pomodoro run: what you're working on,
/// how long each phase lasts, whether sites are blocked, and what plays.
///
/// Assembled in exactly one place. Before this existed, the menu bar read four
/// settings and turned them into argv while the CLI applied its own hardcoded
/// 25/5 defaults, so `focus pomodoro start` quietly ignored Settings. Now both
/// entry points hand their overrides to `fromSettings` and get the same plan.
struct PomodoroPlan: Equatable {
    var goal: String
    var workMinutes: Int
    var breakMinutes: Int
    /// Whether to block sites during work phases.
    var block: Bool
    /// What to play, or nil for silence.
    var station: Station?

    /// Build a plan from the user's settings, with per-run overrides. A nil
    /// override means "use the setting".
    ///
    /// Music precedence: the override > the `pomodoroMusic` setting >
    /// `FOCUS_MUSIC_URI`. Throws if the override names a preset that doesn't exist.
    static func fromSettings(
        goal: String,
        workMinutes: Int? = nil,
        breakMinutes: Int? = nil,
        block: Bool? = nil,
        music: String? = nil
    ) throws -> PomodoroPlan {
        let preset = Defaults.pomodoroMusic
        let target = (music?.isEmpty == false) ? music : (preset.isEmpty ? nil : preset)
        return PomodoroPlan(
            goal: goal,
            workMinutes: workMinutes ?? Defaults.workMinutes,
            breakMinutes: breakMinutes ?? Defaults.breakMinutes,
            block: block ?? Defaults.blockDuringPomodoro,
            station: try Station.resolve(target: target)
        )
    }
}

/// The long-break rhythm, plus whether the run keeps going at all.
///
/// Read afresh at every phase boundary rather than captured at launch, so
/// changing a setting mid-run takes effect at the next boundary. That timing is
/// the reason this is a separate value from `PomodoroPlan`: the plan is fixed
/// for the run, the cadence is not.
struct PomodoroCadence: Equatable {
    var longBreakMinutes: Int
    var sessionsBeforeLongBreak: Int
    /// Keep cycling work → break → work until stopped.
    var keepCycling: Bool
    /// Stop at the end of each set instead of taking the long break, and ask
    /// whether to start another.
    var stopAfterSet: Bool

    static var fromSettings: PomodoroCadence {
        PomodoroCadence(
            longBreakMinutes: Defaults.longBreakMinutes,
            sessionsBeforeLongBreak: Defaults.sessionsBeforeLongBreak,
            keepCycling: Defaults.autoStartNextSession,
            stopAfterSet: Defaults.stopAfterSet
        )
    }
}
