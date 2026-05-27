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
    /// Default off.
    static var autoStartNextSession: Bool {
        get { UserDefaults.standard.bool(forKey: autoStartKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoStartKey) }
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
    /// Empty string means no music auto-start. An http(s):// URL is also accepted.
    static var pomodoroMusic: String {
        get { UserDefaults.standard.string(forKey: pomodoroMusicKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: pomodoroMusicKey) }
    }
}
