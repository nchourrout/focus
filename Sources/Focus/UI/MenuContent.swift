import SwiftUI
import AppKit

struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    /// Today's focused minutes, read once per menu open (onAppear). Kept out of
    /// AppState so the 1 Hz tick never touches the history file.
    @ViewState private var todaysFocus: SessionHistory.Totals?

    var body: some View {
        // Note: no `keyboardShortcut(...)` on the action buttons — those would
        // render as ⌘-equivalents in the menu and imply a global hotkey that
        // doesn't actually exist. Real global bindings are configured in
        // Settings → Shortcuts and handled by the KeyboardShortcuts library.
        if state.isRunning {
            pomodoroSection
        } else if state.pausedSession != nil {
            pausedSection
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
            if state.musicPlaying, state.musicNowPlaying?.presetName == nil {
                Text(state.musicNowPlaying.map { "Now playing: \($0.displayName)" } ?? "Now playing")
                Divider()
            }
            ForEach(Station.presets, id: \.self) { station in
                Toggle(station.displayName, isOn: Binding(
                    get: { state.musicNowPlaying == station },
                    set: { _ in Actions.playMusic(station) }
                ))
            }
            Divider()
            Button("Stop music") { Actions.stopMusic() }
                .disabled(!state.musicPlaying)
        }

        Divider()

        if let focus = todaysFocus, focus.minutes > 0 {
            Text("Today: \(focus.describe()) across \(focus.sessions) sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
        }

        // The standard Settings scene doesn't show its window for LSUIElement
        // menu bar apps. We use a regular Window scene (id: "settings") and
        // open it via the SwiftUI environment action.
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")
        .onAppear {
            // Off the main thread: the log is append-only and unbounded, so
            // parsing it inline would stall the menu for longer every month.
            Task {
                todaysFocus = await Task.detached {
                    SessionHistory.todayTotals(in: SessionHistory.default.entries())
                }.value
            }
        }

        Button("Quit Focus") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
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
            if state.phase == .break {
                Button("Skip break") { Actions.skipBreak() }
            }
            Button("Pause pomodoro") { Actions.pausePomodoro() }
            Button("Stop pomodoro") { Actions.stopPomodoro() }
        }
    }

    @ViewBuilder
    private var pausedSection: some View {
        if let p = state.pausedSession {
            Text("Paused: \(p.goal)")
            Button("Resume pomodoro") { Actions.resumePomodoro() }
            // Discards the frozen record entirely; the CLI's stop handles
            // pid-less (paused) records by just clearing state.
            Button("Discard pomodoro") { Actions.stopPomodoro() }
        }
    }
}
