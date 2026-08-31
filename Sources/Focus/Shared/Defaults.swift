import Foundation

/// User-tunable preferences persisted in UserDefaults. Defaults to the classic
/// 25 / 5 pomodoro split if unset.
enum Defaults {
    /// The app's preference domain, named explicitly rather than left to
    /// `UserDefaults.standard`.
    ///
    /// `.standard` picks its domain from `Bundle.main.bundleIdentifier`, and the
    /// documented install path puts a `/usr/local/bin/focus` symlink on `$PATH`.
    /// Launched through it, the process has no bundle to find and no identifier,
    /// so `.standard` resolves somewhere else entirely and the CLI reads none of
    /// the settings the menu bar app wrote. Naming the suite keeps both halves of
    /// the binary on one domain.
    /// Settable so tests can point at a scratch domain. Naming the real one means
    /// tests would otherwise rewrite the user's live preferences.
    static var store = UserDefaults(suiteName: bundleIdentifier) ?? .standard

    private static let bundleIdentifier = "com.nchourrout.focus"

    private static let workKey = "workMinutes"
    private static let breakKey = "breakMinutes"

    static var workMinutes: Int {
        get {
            let v = store.integer(forKey: workKey)
            return v > 0 ? v : 25
        }
        set {
            store.set(max(1, newValue), forKey: workKey)
        }
    }

    static var breakMinutes: Int {
        get {
            let v = store.integer(forKey: breakKey)
            return v > 0 ? v : 5
        }
        set {
            store.set(max(1, newValue), forKey: breakKey)
        }
    }

    private static let blockKey = "blockDuringPomodoro"

    static var blockDuringPomodoro: Bool {
        // Use object(forKey:) so an unset key reads as the default (true), not
        // false (which is what UserDefaults.bool returns on absence).
        get { store.object(forKey: blockKey) as? Bool ?? true }
        set { store.set(newValue, forKey: blockKey) }
    }

    private static let dohKey = "blockDoHEndpoints"

    /// When on, block/toggle also blackhole common DNS-over-HTTPS endpoints so
    /// browsers configured with "Secure DNS" fall back to the OS resolver
    /// (which honours /etc/hosts). Default on.
    static var blockDoHEndpoints: Bool {
        get { store.object(forKey: dohKey) as? Bool ?? true }
        set { store.set(newValue, forKey: dohKey) }
    }

    /// Argv suffix for `block` / `toggle` reflecting the current DoH preference.
    /// Single source of truth for the flag string — keep in sync with
    /// BlockCommands and the sudoers drop-in.
    static var dohSuppressionFlags: [String] {
        blockDoHEndpoints ? [] : ["--no-block-doh"]
    }

    private static let autoStartKey = "autoStartNextSession"

    /// When on, the pomodoro daemon loops: after the break, it starts another
    /// work/break cycle with the same goal/durations instead of clearing state.
    /// Default on — like every other pomodoro app, Focus keeps the cadence going
    /// (work → break → work …) until you stop it. Use `object(forKey:)` so an
    /// unset key reads as the default (true), not `bool`'s on-absence false.
    static var autoStartNextSession: Bool {
        get { store.object(forKey: autoStartKey) as? Bool ?? true }
        set { store.set(newValue, forKey: autoStartKey) }
    }

    private static let longBreakKey = "longBreakMinutes"

    /// Minutes for the longer break taken every `sessionsBeforeLongBreak`
    /// sessions. Default 15 (classic Pomodoro long break).
    static var longBreakMinutes: Int {
        get {
            let v = store.integer(forKey: longBreakKey)
            return v > 0 ? v : 15
        }
        set { store.set(max(1, newValue), forKey: longBreakKey) }
    }

    private static let sessionsBeforeLongBreakKey = "sessionsBeforeLongBreak"

    /// How many work sessions to complete before the long break replaces the
    /// short one. Default 4 (the canonical pomodoro cadence).
    static var sessionsBeforeLongBreak: Int {
        get {
            let v = store.integer(forKey: sessionsBeforeLongBreakKey)
            return v > 0 ? v : 4
        }
        set { store.set(max(1, newValue), forKey: sessionsBeforeLongBreakKey) }
    }

    private static let stopAfterSetKey = "stopAfterSet"

    /// When on (and cycling is enabled), the daemon stops at the end of each
    /// set — every `sessionsBeforeLongBreak` work sessions — instead of taking
    /// the long break and continuing. It skips that final break, cleans up, and
    /// the menu bar app posts a notification offering to start another set.
    /// Default off, so existing users keep the continuous long-break cadence.
    static var stopAfterSet: Bool {
        get { store.object(forKey: stopAfterSetKey) as? Bool ?? false }
        set { store.set(newValue, forKey: stopAfterSetKey) }
    }

    private static let phaseSoundsKey = "playPhaseSounds"

    /// When on, the menu bar app plays an `NSSound` cue at each phase boundary
    /// (session start, break start, break end). Default on. Independent of
    /// notification sounds so it still fires under Do-Not-Disturb.
    static var playPhaseSounds: Bool {
        get { store.object(forKey: phaseSoundsKey) as? Bool ?? true }
        set { store.set(newValue, forKey: phaseSoundsKey) }
    }

    private static let showGoalKey = "showGoalInMenuBar"

    /// When on, the menu bar shows the running session's goal next to the
    /// countdown. Default off: the menu bar is shared real estate, and a title
    /// that grows with the goal pushes other apps' items off the screen, so
    /// widening it is opt-in. `bool(forKey:)` is right here — its on-absence
    /// false is the default we want.
    static var showGoalInMenuBar: Bool {
        get { store.bool(forKey: showGoalKey) }
        set { store.set(newValue, forKey: showGoalKey) }
    }

    private static let pomodoroStationKey = "pomodoroMusic"

    /// Which `Station` to auto-start when a pomodoro begins, or nil for silence.
    /// Stored as a preset name, so a stale name from an older release (or a URL
    /// written by hand with `defaults write`) reads back as nil rather than
    /// showing a blank selection in Settings. URL-based music is still reachable
    /// through `focus pomodoro start --music https://…`, which overrides this.
    static var pomodoroStation: Station? {
        get { Station(preset: store.string(forKey: pomodoroStationKey) ?? "") }
        set { store.set(newValue?.presetName ?? "", forKey: pomodoroStationKey) }
    }
}
