import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// One shortcut for both start and stop: prompts when no session is active,
    /// stops when one is. Easier to remember than two separate bindings.
    static let togglePomodoro = Self("togglePomodoro")
    static let toggleBlock = Self("toggleBlock")
}

@MainActor
enum HotKeys {
    /// Wire each shortcut to an action. Recorder UI is in SettingsScene; the user
    /// sets and removes bindings there. Library persists them in UserDefaults.
    static func registerAll() {
        // Library dispatches on main but the closure isn't typed as MainActor-isolated.
        // MainActor.assumeIsolated makes that explicit at the type level.
        KeyboardShortcuts.onKeyUp(for: .togglePomodoro) {
            MainActor.assumeIsolated { Actions.togglePomodoro() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleBlock) {
            MainActor.assumeIsolated { Actions.toggleBlock() }
        }
    }
}
