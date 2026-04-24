import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let startPomodoro = Self("startPomodoro")
    static let stopPomodoro = Self("stopPomodoro")
    static let toggleBlock = Self("toggleBlock")
}

@MainActor
enum HotKeys {
    /// Wire each shortcut to an action. Recorder UI is in SettingsScene; the user
    /// sets and removes bindings there. Library persists them in UserDefaults.
    static func registerAll() {
        // Library dispatches on main but the closure isn't typed as MainActor-isolated.
        // Wrapping with MainActor.assumeIsolated makes the isolation explicit and future-proofs
        // against Swift concurrency checks tightening.
        KeyboardShortcuts.onKeyUp(for: .startPomodoro) {
            MainActor.assumeIsolated {
                if PomodoroState.current == nil {
                    Actions.promptAndStartPomodoro()
                }
            }
        }
        KeyboardShortcuts.onKeyUp(for: .stopPomodoro) {
            MainActor.assumeIsolated { Actions.stopPomodoro() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleBlock) {
            MainActor.assumeIsolated { Actions.toggleBlock() }
        }
    }
}
