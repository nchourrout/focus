import AppKit
import SwiftUI
import KeyboardShortcuts

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, blocking, shortcuts, stats, about

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

extension OpenWindowAction {
    /// Bring Settings forward, on `tab` when given, else where it was left.
    /// Works on an already open window too: the tab is read from defaults.
    @MainActor func settings(_ tab: SettingsTab? = nil) {
        if let tab { Defaults.settingsTab = tab.rawValue }
        NSApp.activate(ignoringOtherApps: true)
        self(id: "settings")
    }
}

struct SettingsContent: View {
    @AppStorage(Defaults.settingsTabKey, store: Defaults.store) private var tab: SettingsTab = .general

    var body: some View {
        // A segmented control over the content rather than a TabView. In a
        // plain Window, TabView draws its box flush under the title bar with
        // the tabs straddling the seam, which read as a layout bug. The
        // Settings scene would give real toolbar tabs, but it doesn't reliably
        // show for a menu bar app (see FocusApp).
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(SettingsTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 4)
            .padding(.bottom, 10)

            Divider()

            Group {
                switch tab {
                case .general: GeneralTab()
                case .blocking: BlockingTab()
                case .shortcuts: ShortcutsTab()
                case .stats: StatsTab()
                case .about: AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Sized to fit the General tab, the tallest, under the section picker.
        // Each Form still scrolls on its own at large accessibility text sizes.
        .frame(width: 500, height: 650)
    }
}

private struct GeneralTab: View {
    /// Bumped after a setting or SMAppService state changes, so the read-only
    /// computed properties re-evaluate.
    @ViewState private var refreshTick = 0

    var body: some View {
        Form {
            Section("Session") {
                IncrementControl("Work", value: workBinding, range: 1...180, step: 5, unit: "min")
                IncrementControl("Break", value: breakBinding, range: 1...60, unit: "min")
                Toggle("Block websites while working", isOn: blockDuringPomodoroBinding)
                Picker("Start music with pomodoro", selection: pomodoroStationBinding) {
                    Text("None").tag(Station?.none)
                    ForEach(Station.presets, id: \.self) { station in
                        Text(station.displayName).tag(Station?.some(station))
                    }
                }
                Toggle("Play a sound at each phase change", isOn: phaseSoundsBinding)
                Toggle("Show the goal in the menu bar", isOn: showGoalBinding)
            }

            Section {
                Toggle("Keep cycling sessions until I stop", isOn: autoStartBinding)
                IncrementControl(
                    "Long break after every", value: sessionsBinding, range: 1...12,
                    unit: sessionsBeforeLongBreak == 1 ? "session" : "sessions"
                )
                .disabled(!autoStart)
                IncrementControl("Long break", value: longBreakBinding, range: 1...60, step: 5, unit: "min")
                    .disabled(!autoStart)
            } header: {
                Text("Cycling")
            } footer: {
                Text(cyclingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("System") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
            }
        }
        .formStyle(.grouped)
    }

    /// Spells out what the three cycling controls add up to, so the user doesn't
    /// have to simulate them in their head.
    private var cyclingSummary: String {
        guard autoStart else {
            // Even a single run takes the long break when every break is long.
            let breakLength = sessionsBeforeLongBreak == 1 ? longBreakMinutes : breakMinutes
            return "One \(workMinutes) min work phase, one \(breakLength) min break, then Focus stops."
        }
        let every = sessionsBeforeLongBreak
        let sessions = "\(every) session\(every == 1 ? "" : "s")"
        return "Runs continuously, taking a \(longBreakMinutes) min break after every \(sessions) instead of \(breakMinutes) min."
    }

    private var workMinutes: Int { _ = refreshTick; return Defaults.workMinutes }
    private var breakMinutes: Int { _ = refreshTick; return Defaults.breakMinutes }
    private var longBreakMinutes: Int { _ = refreshTick; return Defaults.longBreakMinutes }
    private var sessionsBeforeLongBreak: Int { _ = refreshTick; return Defaults.sessionsBeforeLongBreak }
    private var autoStart: Bool { _ = refreshTick; return Defaults.autoStartNextSession }

    /// Wrap a Defaults accessor in a Binding that bumps `refreshTick` on every
    /// write, so dependent computed properties re-evaluate. Use this for the
    /// straightforward "read X, write X, refresh" pattern; bindings with side
    /// effects (sound cues, reapplyBlock, SMAppService) build their own.
    private func defaultsBinding<T>(
        get: @escaping () -> T,
        set: @escaping (T) -> Void
    ) -> Binding<T> {
        Binding(
            get: { _ = refreshTick; return get() },
            set: { set($0); refreshTick += 1 }
        )
    }

    private var workBinding: Binding<Int> {
        defaultsBinding(get: { Defaults.workMinutes }, set: { Defaults.workMinutes = $0 })
    }
    private var breakBinding: Binding<Int> {
        defaultsBinding(get: { Defaults.breakMinutes }, set: { Defaults.breakMinutes = $0 })
    }
    private var blockDuringPomodoroBinding: Binding<Bool> {
        defaultsBinding(get: { Defaults.blockDuringPomodoro }, set: { Defaults.blockDuringPomodoro = $0 })
    }
    private var autoStartBinding: Binding<Bool> {
        defaultsBinding(get: { Defaults.autoStartNextSession }, set: { Defaults.autoStartNextSession = $0 })
    }
    private var longBreakBinding: Binding<Int> {
        defaultsBinding(get: { Defaults.longBreakMinutes }, set: { Defaults.longBreakMinutes = $0 })
    }
    private var sessionsBinding: Binding<Int> {
        defaultsBinding(get: { Defaults.sessionsBeforeLongBreak }, set: { Defaults.sessionsBeforeLongBreak = $0 })
    }
    private var pomodoroStationBinding: Binding<Station?> {
        Binding(
            get: { _ = refreshTick; return Defaults.pomodoroStation },
            set: { newValue in
                guard newValue != Defaults.pomodoroStation else { return }
                Defaults.pomodoroStation = newValue
                refreshTick += 1
                // If music is already playing, switch it live so the change is
                // audible immediately rather than only at the next start.
                Actions.reapplyMusic(newValue)
            }
        )
    }

    private var showGoalBinding: Binding<Bool> {
        defaultsBinding(get: { Defaults.showGoalInMenuBar }, set: { Defaults.showGoalInMenuBar = $0 })
    }

    private var phaseSoundsBinding: Binding<Bool> {
        Binding(
            get: { _ = refreshTick; return Defaults.playPhaseSounds },
            set: { newValue in
                Defaults.playPhaseSounds = newValue
                refreshTick += 1
                // Audible feedback when the toggle is flipped on, so the user
                // hears what kind of cue they've just enabled.
                if newValue { Sounds.play(.sessionStart) }
            }
        )
    }

    /// Reads `SMAppService.mainApp.status` on every access so the toggle always
    /// reflects the live state, not a snapshot from view init.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { _ = refreshTick; return LaunchAtLogin.isEnabled },
            set: { newValue in
                LaunchAtLogin.set(newValue)
                refreshTick += 1
            }
        )
    }
}

private struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Start / stop pomodoro", name: .togglePomodoro)
                KeyboardShortcuts.Recorder("Toggle website block", name: .toggleBlock)
            } footer: {
                Text("These work anywhere, even when Focus isn't the active app. Click a field and press the combination you want, or use the clear button to remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// Everything that decides what a block does: whether Focus may apply it,
/// whether DNS-over-HTTPS gets around it, and the sites it covers.
private struct BlockingTab: View {
    @ViewState private var content: String = ""
    @ViewState private var error: String?
    @ViewState private var loaded = false
    @ViewState private var saveTask: Task<Void, Never>?
    /// Bumped after the sudoers drop-in or a setting changes, so the read-only
    /// computed properties re-evaluate.
    @ViewState private var refreshTick = 0
    @ViewState private var installError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button(permissionButtonTitle) {
                        installPermission()
                    }
                } label: {
                    Label {
                        Text(permissionLabel)
                    } icon: {
                        Image(systemName: permissionStatus == .current
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(permissionStatus == .current ? .green : .orange)
                    }
                }

                if let installError {
                    Text(installError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Block DNS-over-HTTPS endpoints", isOn: blockDoHBinding)
            } footer: {
                Text("Editing /etc/hosts needs a one-time admin password. Blocking DNS-over-HTTPS makes browsers with Secure DNS fall back to the system resolver, so blocks aren't bypassed. Turn it off if you rely on Cloudflare WARP or iCloud Private Relay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    // Fixed, so a long list scrolls inside the editor instead
                    // of growing the Form past the window.
                    .frame(height: 300)
            } header: {
                Text("Sites")
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    if let error {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).foregroundStyle(.red)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        // Verbatim: as markdown, "www." renders as a link.
                        Text(verbatim: "One site per line, # for comments. www., m. and mobile. are added automatically. Saved; applies the next time the block turns on, including at each work phase.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            load()
        }
        // Debounce: each keystroke pushed a full file write + re-parse, and the
        // inline status flashed red on every transiently-invalid mid-edit line.
        // Coalesce edits, then flush immediately when the window closes so the
        // last keystrokes aren't lost.
        .onChange(of: content) { _ in
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                save()
            }
        }
        .onDisappear {
            // Only flush a genuinely pending edit. If load() failed, content is
            // still "" and no edit ever fired, so saveTask is nil — don't clobber
            // the on-disk list with an empty write.
            guard saveTask != nil else { return }
            saveTask?.cancel()
            save()
        }
    }

    private var permissionStatus: SudoersInstaller.Status {
        _ = refreshTick
        return SudoersInstaller.status
    }

    private var permissionLabel: String {
        switch permissionStatus {
        case .missing: return "Not granted"
        // Still works, but runs an older build of the helper, or trusts the
        // user-writable binary (drop-ins from before the helper existed).
        case .outdated: return "Granted, needs update"
        case .current: return "Granted"
        }
    }

    private var permissionButtonTitle: String {
        switch permissionStatus {
        case .missing: return "Grant…"
        case .outdated: return "Update…"
        case .current: return "Reinstall…"
        }
    }

    private func installPermission() {
        installError = nil
        SudoersInstaller.installWithUI(
            onSuccess: { refreshTick += 1 },
            onError: { error in installError = error.localizedDescription }
        )
    }

    private var blockDoHBinding: Binding<Bool> {
        Binding(
            get: { _ = refreshTick; return Defaults.blockDoHEndpoints },
            set: { newValue in
                guard newValue != Defaults.blockDoHEndpoints else { return }
                Defaults.blockDoHEndpoints = newValue
                refreshTick += 1
                Actions.reapplyBlock()
            }
        )
    }

    private func load() {
        do {
            let url = try BlockList.ensureUserFile()
            content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        do {
            let url = try BlockList.ensureUserFile()
            // Validate first and keep the last good file on disk. Writing an
            // invalid list made every later `sudo focus block` fail, and the
            // daemon only logs that, so whole sessions ran unblocked.
            _ = try BlockList.parse(content, path: url)
            try content.write(to: url, atomically: true, encoding: .utf8)
            error = nil
        } catch {
            self.error = "Not saved: " + error.localizedDescription
        }
    }
}

/// Wide minus and plus targets either side of the value, in place of a
/// stepper, whose arrows were too small to hit reliably. A click moves to the
/// next multiple of `step`, so a 23 set from the CLI goes to 25 or 20 rather
/// than 28 or 18. Holding a button repeats, on macOS 14 and later.
struct IncrementControl: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let unit: String

    init(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, unit: String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) { control }
    }

    private var control: some View {
        HStack(spacing: 0) {
            button("minus", by: -step, help: "Less")
            Text("\(value) \(unit)")
                .monospacedDigit()
                // LabeledContent dims its content as secondary; the value is
                // the point of the row.
                .foregroundStyle(.primary)
                .frame(minWidth: 84)
                .overlay(alignment: .leading) { Divider() }
                .overlay(alignment: .trailing) { Divider() }
            button("plus", by: step, help: "More")
        }
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        .fixedSize()
        // One adjustable element for VoiceOver, as the Stepper was, rather than
        // two bare buttons and a stray value.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = Self.stepped(value, by: step, in: range)
            case .decrement: value = Self.stepped(value, by: -step, in: range)
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, by delta: Int, help: String) -> some View {
        Button {
            value = Self.stepped(value, by: delta, in: range)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(Self.stepped(value, by: delta, in: range) == value)
        .repeatsWhileHeld()
        .help(help)
    }

    /// The value one click of `delta` away: the next multiple of it in that
    /// direction, clamped to `range`. A value already past the end it moves
    /// toward stays put, so "More" never lowers one set out of range.
    static func stepped(_ value: Int, by delta: Int, in range: ClosedRange<Int>) -> Int {
        if delta > 0, value >= range.upperBound { return value }
        if delta < 0, value <= range.lowerBound { return value }
        let size = max(abs(delta), 1)
        let next = delta > 0 ? (value / size + 1) * size : ((value - 1) / size) * size
        return min(max(next, range.lowerBound), range.upperBound)
    }
}

private extension View {
    @ViewBuilder func repeatsWhileHeld() -> some View {
        if #available(macOS 14.0, *) {
            buttonRepeatBehavior(.enabled)
        } else {
            self
        }
    }
}

/// What this build is and where it comes from.
private struct AboutTab: View {
    private static let repo = URL(string: "https://github.com/nchourrout/focus")!

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Focus").font(.title.weight(.semibold))
            Text("Version \(focusVersion())")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Block distracting sites, play focus music and run pomodoros, from the menu bar or the terminal.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HStack(spacing: 18) {
                Link("Source code", destination: Self.repo)
                Link("Releases", destination: Self.repo.appendingPathComponent("releases"))
                Link("Report an issue", destination: Self.repo.appendingPathComponent("issues"))
            }
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 4) {
                Text("Music streams courtesy of [SomaFM](https://somafm.com), listener-supported radio.")
                if let copyright = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String {
                    Text("\(copyright) MIT License.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 48)
        .padding([.horizontal, .bottom], 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
