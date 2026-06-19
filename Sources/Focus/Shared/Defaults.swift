import Foundation

/// User-tunable preferences persisted in UserDefaults. Defaults to the classic
/// 25 / 5 pomodoro split if unset.
enum Defaults {
    private static let workKey = "workMinutes"
    private static let breakKey = "breakMinutes"

    static var workMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: workKey)
            return v > 0 ? v : 25
        }
        set {
            UserDefaults.standard.set(max(1, newValue), forKey: workKey)
        }
    }

    static var breakMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: breakKey)
            return v > 0 ? v : 5
        }
        set {
            UserDefaults.standard.set(max(1, newValue), forKey: breakKey)
        }
    }

    private static let blockKey = "blockDuringPomodoro"

    static var blockDuringPomodoro: Bool {
        // Use object(forKey:) so an unset key reads as the default (true), not
        // false (which is what UserDefaults.bool returns on absence).
        get { UserDefaults.standard.object(forKey: blockKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: blockKey) }
    }

    private static let dohKey = "blockDoHEndpoints"

    /// When on, block/toggle also blackhole common DNS-over-HTTPS endpoints so
    /// browsers configured with "Secure DNS" fall back to the OS resolver
    /// (which honours /etc/hosts). Default on.
    static var blockDoHEndpoints: Bool {
        get { UserDefaults.standard.object(forKey: dohKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: dohKey) }
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
        get { UserDefaults.standard.object(forKey: autoStartKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoStartKey) }
    }

    private static let longBreakKey = "longBreakMinutes"

    /// Minutes for the longer break taken every `sessionsBeforeLongBreak`
    /// sessions. Default 15 (classic Pomodoro long break).
    static var longBreakMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: longBreakKey)
            return v > 0 ? v : 15
        }
        set { UserDefaults.standard.set(max(1, newValue), forKey: longBreakKey) }
    }

    private static let sessionsBeforeLongBreakKey = "sessionsBeforeLongBreak"

    /// How many work sessions to complete before the long break replaces the
    /// short one. Default 4 (the canonical pomodoro cadence).
    static var sessionsBeforeLongBreak: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: sessionsBeforeLongBreakKey)
            return v > 0 ? v : 4
        }
        set { UserDefaults.standard.set(max(1, newValue), forKey: sessionsBeforeLongBreakKey) }
    }

    private static let phaseSoundsKey = "playPhaseSounds"

    /// When on, the menu bar app plays an `NSSound` cue at each phase boundary
    /// (session start, break start, break end). Default on. Independent of
    /// notification sounds so it still fires under Do-Not-Disturb.
    static var playPhaseSounds: Bool {
        get { UserDefaults.standard.object(forKey: phaseSoundsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: phaseSoundsKey) }
    }

    private static let pomodoroMusicKey = "pomodoroMusic"

    /// Preset name (see `MusicPresets`) to auto-start when a pomodoro begins.
    /// Empty string means no music auto-start. Stored values that aren't a
    /// known preset (a stale name from an older release, or a URL set via
    /// `defaults write`) read back as "" so the Settings Picker doesn't show
    /// a blank selection. URL-based music is still reachable through the CLI's
    /// `focus pomodoro start --music https://...`, which bypasses this default.
    static var pomodoroMusic: String {
        get {
            let raw = UserDefaults.standard.string(forKey: pomodoroMusicKey) ?? ""
            return MusicPresets.names.contains(raw) ? raw : ""
        }
        set { UserDefaults.standard.set(newValue, forKey: pomodoroMusicKey) }
    }
}
