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
                Text(nowPlayingDisplay.map { "Now playing: \($0)" } ?? "Now playing")
                Divider()
            }
            ForEach(MusicPresets.list, id: \.name) { preset in
                Toggle(preset.name.capitalized, isOn: Binding(
                    get: { currentPresetName == preset.name },
                    set: { _ in Actions.playMusic(preset.name) }
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
    /// non-preset stream. Drives both the submenu checkmark and the title.
    private var currentPresetName: String? {
        guard let label = state.musicNowPlaying,
              MusicPresets.names.contains(label) else { return nil }
        return label
    }

    /// Short human label for the current stream: preset name capitalized,
    /// custom URL reduced to its host, local file shown by name.
    private var nowPlayingDisplay: String? {
        guard let label = state.musicNowPlaying else { return nil }
        if MusicPresets.names.contains(label) { return label.capitalized }
        if label.contains("://") { return URL(string: label)?.host ?? label }
        return label
    }

    private var musicTitle: String {
        guard state.musicPlaying else { return "Music" }
        guard let display = nowPlayingDisplay else { return "Music ♪" }
        return "Music ♪ \(display)"
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
