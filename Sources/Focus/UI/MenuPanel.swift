import AppKit
import SwiftUI

/// The menu bar panel: the session at the top, today's tasks in the middle,
/// block, music and settings at the bottom.
///
/// A window-style MenuBarExtra rather than a native menu, because a task list
/// needs what NSMenu can't give: a checkbox that ticks without closing
/// anything, a text field to type the next task, a countdown that moves.
struct MenuPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SessionHeader(state: state)
                .padding(14)
            Divider()
            TodayList(state: state)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Divider()
            PanelFooter(state: state)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 300)
        // The content's own height, never the window's: `PanelWindow` sizes
        // the window from it.
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .background(PanelWindow())
    }
}

/// Two fixes to the window-style MenuBarExtra's own window, made from a view
/// in the content's background, which SwiftUI sizes to the content.
///
/// The window is glass by default, and on recent macOS that is translucent
/// enough to read the window behind it through the task list, so it is made
/// opaque.
///
/// It also grows with its content but never shrinks back: once a session or a
/// few tasks had made it tall, an emptier panel sat in a blank band of the old
/// height. So the window is held to this view's height, with its top edge kept
/// under the menu bar.
private struct PanelWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            // The glass lives in a visual-effect view under the content; an
            // opaque window still shows it, so switch it off.
            for effect in window.contentView?.superview?.subviewsDeep(of: NSVisualEffectView.self) ?? [] {
                effect.state = .inactive
                effect.material = .windowBackground
            }
            fitWindow()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            // Out of the layout pass that sized us: resizing the window from
            // inside it would re-enter the hosting view's layout.
            DispatchQueue.main.async { [weak self] in self?.fitWindow() }
        }

        private func fitWindow() {
            let height = bounds.height
            guard let window, height > 0 else { return }
            let current = window.contentRect(forFrameRect: window.frame).height
            guard abs(height - current) > 0.5 else { return }
            var frame = window.frame
            frame.origin.y += current - height
            frame.size.height += height - current
            window.setFrame(frame, display: false)
        }
    }
}

private extension NSView {
    func subviewsDeep<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { (($0 as? T).map { [$0] } ?? []) + $0.subviewsDeep(of: type) }
    }
}

// MARK: - Session

private struct SessionHeader: View {
    @ObservedObject var state: AppState
    /// The goal typed in place of the suggested task, while "Other goal…" is open.
    @ViewState private var customGoal = ""
    @ViewState private var typingGoal = false
    @FocusState private var goalFieldFocused: Bool

    var body: some View {
        Group {
            if let p = state.pomodoro, state.isRunning {
                running(p)
            } else if let p = state.pausedSession {
                paused(p)
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func running(_ p: PomodoroSession.Active) -> some View {
        // Built outside the tick: neither the task list nor the setting it
        // reads changes from one second to the next.
        let goal = goalLine(p)
        // With every task ticked there is no session to skip to: skip-break
        // would end the run, which Stop already says plainly.
        let canSkipBreak = TodoList.nextGoal(after: p.goal, in: state.todos) != nil
        // The panel only exists on screen while open, so ticking here costs
        // nothing the rest of the day.
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date.timeIntervalSince1970
            let (phase, timeLeft) = PomodoroSession.default.phase(of: p, at: now)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(phaseLabel(p, phase)).capsLabel()
                    Spacer()
                    if let position = setPosition(p) {
                        Text(position).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(formatCountdown(timeLeft)).countdown()
                goal
                ProgressView(value: progress(p, phase, timeLeft))
                    .tint(phase == .break ? .green : .accentColor)
                HStack(spacing: 8) {
                    if phase == .break, canSkipBreak {
                        Button("Skip break") { Actions.skipBreak() }
                    }
                    Button("Pause") { Actions.pausePomodoro() }
                    Button("Stop") { Actions.stopPomodoro() }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    private func paused(_ p: PomodoroSession.Active) -> some View {
        let timeLeft = PomodoroSession.default.phase(of: p, at: p.pausedAt ?? 0).timeLeft
        return VStack(alignment: .leading, spacing: 6) {
            Text("Paused").capsLabel()
            Text(formatCountdown(timeLeft)).countdown().foregroundStyle(.secondary)
            goalLine(p)
            HStack(spacing: 8) {
                Button("Resume") { Actions.resumePomodoro() }
                Button("Discard") { Actions.stopPomodoro() }
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
    }

    /// The goal, ticked once its task is done, with what the run does about
    /// it: the session still runs out, and the next one moves on (see
    /// `TodoList.nextGoal`).
    @ViewBuilder
    private func goalLine(_ p: PomodoroSession.Active) -> some View {
        let next = TodoList.nextGoal(after: p.goal, in: state.todos)
        if next == p.goal {
            Text(p.goal).font(.headline).lineLimit(2)
        } else {
            Label {
                Text(p.goal).lineLimit(2)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            // Named whether or not cycling is on: Skip break starts on it too.
            Text(next.map { "Up next: \($0)" } ?? "All done. Focus stops after this break.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var idle: some View {
        let suggested = state.todos.first { !$0.isDone }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ready").capsLabel()
                Spacer()
                Text(formatCountdown(TimeInterval(Defaults.workMinutes * 60)))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if typingGoal {
                HStack(spacing: 6) {
                    TextField("What are you working on?", text: $customGoal)
                        .textFieldStyle(.roundedBorder)
                        .focused($goalFieldFocused)
                        .onSubmit(startCustomGoal)
                        .onExitCommand { typingGoal = false; customGoal = "" }
                    Button(action: startCustomGoal) {
                        Image(systemName: "play.fill")
                    }
                    .disabled(customGoal.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if let suggested {
                Button {
                    Actions.startPomodoro(goal: suggested.title)
                } label: {
                    Label("Start on \u{201C}\(suggested.title)\u{201D}", systemImage: "play.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Other goal\u{2026}") {
                    typingGoal = true
                    goalFieldFocused = true
                }
                .buttonStyle(.link)
                .font(.caption)
            } else {
                // Nothing to suggest. One field to type into, the task list's,
                // rather than two stacked ones asking much the same thing.
                Text("Add a task below to start on it.")
                    .foregroundStyle(.secondary)
                Button("Or just type a goal\u{2026}") {
                    typingGoal = true
                    goalFieldFocused = true
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private func startCustomGoal() {
        let goal = customGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        Actions.startPomodoro(goal: goal)
        customGoal = ""
        typingGoal = false
    }

    private func phaseLabel(_ p: PomodoroSession.Active, _ phase: PomodoroSession.Phase) -> String {
        switch phase {
        case .work: return "Focus"
        case .break: return p.isLongBreak ? "Long break" : "Break"
        case .done: return "Done"
        }
    }

    /// "Session 2 of 4" while cycling: where this session sits before the long
    /// break. Nothing for a one-off session, where it would always read "1 of 1".
    private func setPosition(_ p: PomodoroSession.Active) -> String? {
        guard Defaults.autoStartNextSession else { return nil }
        let every = max(Defaults.sessionsBeforeLongBreak, 1)
        return "Session \((p.sessionNumber - 1) % every + 1) of \(every)"
    }

    private func progress(_ p: PomodoroSession.Active, _ phase: PomodoroSession.Phase,
                          _ timeLeft: TimeInterval) -> Double {
        let length = phase == .break ? p.breakEnd - p.workEnd : p.workEnd - p.startedAt
        guard length > 0 else { return 1 }
        return min(max(1 - timeLeft / length, 0), 1)
    }
}

// MARK: - Today

private struct TodayList: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @ViewState private var newTask = ""
    /// Shown under the field when an add fails, usually a full list filled
    /// from a terminal while the panel was open.
    @ViewState private var addError: String?

    private var openCount: Int { state.todos.filter { !$0.isDone }.count }
    private var doneCount: Int { state.todos.count - openCount }
    private var isFull: Bool { openCount >= TodoList.maxOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Today").capsLabel()
                Spacer()
                let focused = state.focusedToday
                if focused.minutes > 0 {
                    Button("\(focused.describe()) focused") { openWindow.settings(.stats) }
                        .buttonStyle(.plain)
                        .help("Focused \(focused.summary()) today. Click for stats.")
                }
                if !state.todos.isEmpty {
                    if focused.minutes > 0 { Text("\u{00B7}") }
                    Text("\(doneCount) of \(state.todos.count) done")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            ForEach(state.todos) { item in
                TodoRow(
                    item: item,
                    isCurrent: isCurrent(item),
                    canStart: !state.isRunning && state.pausedSession == nil,
                    canReopen: !isFull
                )
            }
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
                if isFull {
                    Text("\(TodoList.maxOpen) open tasks. Finish one first")
                        .foregroundStyle(.tertiary)
                } else {
                    TextField("", text: $newTask, prompt: Text(placeholder).foregroundColor(.secondary))
                        .textFieldStyle(.plain)
                        .onSubmit(add)
                }
            }
            .padding(.vertical, 4)
            if let addError {
                Text(addError).font(.caption).foregroundStyle(.red)
            }
        }
        .onChange(of: state.todos) { _ in addError = nil }
    }

    private var placeholder: String {
        state.todos.isEmpty ? "What matters today?" : "Add a task"
    }

    private func add() {
        let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            try TodoList.default.add(title)
            newTask = ""
            addError = nil
        } catch {
            addError = error.localizedDescription
        }
    }

    /// The task the running or paused session is on, matched by title since
    /// a session only carries its goal.
    private func isCurrent(_ item: TodoList.Item) -> Bool {
        guard !item.isDone else { return false }
        let goal = state.isRunning ? state.pomodoro?.goal : state.pausedSession?.goal
        return goal == item.title
    }
}

private struct TodoRow: View {
    let item: TodoList.Item
    let isCurrent: Bool
    let canStart: Bool
    /// Reopening a done task counts against the cap, same as adding one.
    let canReopen: Bool
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Actions.setTodoDone(item.id, !item.isDone)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .disabled(item.isDone && !canReopen)
            .help(item.isDone ? "Mark not done" : "Mark done")

            Text(item.title)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if isCurrent {
                Text("NOW")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
            }
            if hovering {
                if canStart, !item.isDone {
                    iconButton("play.fill", help: "Start a pomodoro on this") {
                        Actions.startPomodoro(goal: item.title)
                    }
                }
                iconButton("xmark", help: "Remove") { Actions.removeTodo(item.id) }
            }
        }
        // Match the 20pt hover buttons so revealing them doesn't grow the row.
        .frame(minHeight: 20)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

// MARK: - Footer

private struct PanelFooter: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 6) {
            Button {
                Actions.toggleBlock()
            } label: {
                Label(state.blockActive ? "Blocked" : "Block", systemImage: "nosign")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(Chip(active: state.blockActive))
            .help(state.blockActive ? "Unblock websites" : "Block websites")

            // One chip, two targets: the station menu, and play/pause beside it.
            HStack(spacing: 2) {
                Menu {
                    ForEach(Station.presets, id: \.self) { station in
                        Toggle(station.displayName, isOn: Binding(
                            get: { state.musicNowPlaying == station },
                            set: { _ in Actions.playMusic(station) }
                        ))
                    }
                    Divider()
                    Button("Stop music") { Actions.stopMusic() }
                        .disabled(!state.musicPlaying)
                } label: {
                    Label(musicTitle, systemImage: "music.note")
                        .font(.caption)
                        .lineLimit(1)
                }
                .controlSize(.small)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.leading, 8)
                .padding(.vertical, 4)
                playPauseButton
            }
            .chipBackground(active: state.musicPlaying)

            Spacer(minLength: 4)

            Menu {
                Button("Settings\u{2026}  \u{2318},", action: openSettings)
                Button("Quit Focus  \u{2318}Q") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.caption)
        // Shortcuts on the gear menu's items would only fire while that menu
        // is open; these work whenever the panel has focus.
        .background {
            Group {
                Button("", action: openSettings)
                    .keyboardShortcut(",")
                Button("") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    private func openSettings() {
        openWindow.settings()
    }

    /// Pause and play without opening the station menu. A stream has no
    /// pause of its own, so this stops it, and play reconnects to whatever
    /// played last.
    private var playPauseButton: some View {
        let playing = state.musicPlaying
        let resume = Defaults.lastStation ?? Defaults.pomodoroStation ?? Station.presets[0]
        return Button {
            if playing {
                Actions.stopMusic()
            } else {
                Actions.playMusic(resume)
            }
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .help(playing ? pauseHelp : "Play \(resume.displayName)")
    }

    /// A file restarts from the top on play rather than resuming, so its
    /// button says what it really does.
    private var pauseHelp: String {
        if case .file = state.musicNowPlaying { return "Stop music" }
        return "Pause music"
    }

    private var musicTitle: String {
        guard state.musicPlaying else { return "Music" }
        return state.musicNowPlaying?.displayName ?? "Playing"
    }
}

/// A small rounded toggle-like button for the footer.
private struct Chip: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .chipBackground(active: active, pressed: configuration.isPressed)
    }
}

private extension View {
    func chipBackground(active: Bool, pressed: Bool = false) -> some View {
        self
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .background(
                Capsule().fill(
                    active ? Color.accentColor.opacity(pressed ? 0.3 : 0.16)
                        : Color.primary.opacity(pressed ? 0.14 : 0.07)
                )
            )
    }

    func capsLabel() -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    func countdown() -> some View {
        self
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }
}
