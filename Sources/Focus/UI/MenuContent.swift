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

        Menu(musicTitle) {
            // A checkmark marks the playing preset below; the header is only
            // needed when the stream isn't a preset (custom URL, local file,
            // or a label-less PID file from an older build).
            if state.musicPlaying, currentPresetName == nil {
                Text(state.musicNowPlaying.map { "Now playing: \($0.displayName)" } ?? "Now playing")
                Divider()
            }
            ForEach(MusicPresets.list, id: \.name) { preset in
                Toggle(preset.name.capitalized, isOn: Binding(
                    get: { currentPresetName == preset.name },
                    set: { _ in Actions.playMusic(.preset(preset.name)) }
                ))
            }
            Divider()
            Button("Stop music") { Actions.stopMusic() }
                .disabled(!state.musicPlaying)
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

    /// The playing station's preset name, or nil when stopped / playing a
    /// non-preset stream. Drives the submenu checkmark.
    private var currentPresetName: String? {
        state.musicNowPlaying?.presetName
    }

    private var musicTitle: String {
        guard state.musicPlaying else { return "Music" }
        guard let station = state.musicNowPlaying else { return "Music ♪" }
        return "Music ♪ \(station.displayName)"
    }

    @ViewBuilder
    private var pomodoroSection: some View {
        if let p = state.pomodoro {
            // No live countdown here — the menu bar label has it, and re-rendering
            // a menu item every second would reset AppKit's hover selection.
            Text(state.phase == .break ? (p.isLongBreak ? "Long break" : "Break") : p.goal)
            Button("Stop pomodoro") { Actions.stopPomodoro() }
        }
    }
}
