import SwiftUI
import AppKit

struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Note: no `keyboardShortcut(...)` on the action buttons — those would
        // render as ⌘-equivalents in the menu and imply a global hotkey that
        // doesn't actually exist. Real global bindings are configured in
        // Settings → Shortcuts and handled by the KeyboardShortcuts library.
        if state.isRunning {
            pomodoroSection
        } else {
            Button("Start pomodoro…") { Actions.promptAndStartPomodoro() }
        }

        Divider()

        Button(state.blockActive ? "Unblock websites" : "Block websites") {
            Actions.toggleBlock()
        }

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

        // The standard Settings scene doesn't show its window for LSUIElement
        // menu bar apps. We use a regular Window scene (id: "settings") and
        // open it via the SwiftUI environment action.
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
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
        }
    }
}
