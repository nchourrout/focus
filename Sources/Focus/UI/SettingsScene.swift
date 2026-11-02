import SwiftUI
import KeyboardShortcuts

struct SettingsContent: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            BlockingTab()
                .tabItem { Label("Blocking", systemImage: "nosign") }

            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            StatsTab()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
        // Sized to fit the General tab, the tallest. It used to also carry the
        // block permission and DNS settings and needed 864pt; those now live on
        // the Blocking tab, next to the list they apply to. Each Form still
        // scrolls on its own at large accessibility text sizes.
        .frame(width: 500, height: 640)
    }
}

private struct GeneralTab: View {
    /// Bumped after a setting or SMAppService state changes, so the read-only
    /// computed properties re-evaluate.
    @ViewState private var refreshTick = 0

    var body: some View {
        Form {
            Section("Session") {
                Stepper("Work: \(workMinutes) min", value: workBinding, in: 1...180)
                Stepper("Break: \(breakMinutes) min", value: breakBinding, in: 1...60)
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
                Stepper(
                    "Long break after every \(sessionsBeforeLongBreak) session\(sessionsBeforeLongBreak == 1 ? "" : "s")",
                    value: sessionsBinding, in: 1...12
                )
                .disabled(!autoStart)
                Stepper("Long break: \(longBreakMinutes) min", value: longBreakBinding, in: 1...60)
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
                    .frame(minHeight: 220)
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
