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
        KeyboardShortcuts.onKeyUp(for: .startPomodoro) {
            if PomodoroState.current == nil {
                Actions.promptAndStartPomodoro()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .stopPomodoro) {
            Actions.stopPomodoro()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleBlock) {
            Actions.toggleBlock()
        }
    }
}
