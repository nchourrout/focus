import SwiftUI
import AppKit

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.isRunning {
            pomodoroSection
        } else {
            Button("Start pomodoro…") { Actions.promptAndStartPomodoro() }
                .keyboardShortcut("o")
        }

        Divider()

        Button(state.blockActive ? "Unblock websites" : "Block websites") {
            Actions.toggleBlock()
        }
        .keyboardShortcut("b")

        Menu("Music") {
            ForEach(MusicPresets.list, id: \.name) { preset in
                Button(preset.name.capitalized) {
                    Actions.playMusic(preset.name)
                }
            }
            Divider()
            Button("Stop music") { Actions.stopMusic() }
        }

        Divider()

        // SettingsLink (macOS 14+) doesn't reliably open the Settings scene from a
        // MenuBarExtra in an LSUIElement (accessory) app — the scene gets created
        // but the window never comes forward. Activating + dispatching
        // showSettingsWindow: works on both 13 and 14+.
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                return
            }
            // Older selector name used pre-macOS 13.
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",")

        Button("Quit Focus") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var pomodoroSection: some View {
        if let p = state.pomodoro {
            // Disabled items are the idiomatic way to show read-only status in a menu.
            Text(state.phase == .break ? "Break — \(formatCountdown(state.timeLeft))"
                                       : "\(p.goal) — \(formatCountdown(state.timeLeft))")
            Button("Stop pomodoro") { Actions.stopPomodoro() }
                .keyboardShortcut("o")
        }
    }
}
