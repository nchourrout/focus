import SwiftUI
import KeyboardShortcuts

struct SettingsContent: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            BlockListTab()
                .tabItem { Label("Block list", systemImage: "nosign") }
        }
        // Sized to fit the General tab's content, which is the tallest. Grouped
        // Form rows are roomier than the hand-spaced VStack this replaced, so the
        // window is taller than it looks like it needs to be: at 620 the System
        // section fell below the fold, which hides the "Grant permission" button
        // — the one control a user goes looking for when blocking isn't working.
        // The Form still scrolls on its own at large accessibility text sizes,
        // and on the Block list tab.
        .frame(width: 500, height: 864)
    }
}

private struct GeneralTab: View {
    /// Bumped after SMAppService or sudoers-drop-in state changes, so the
    /// read-only computed properties re-evaluate.
    @ViewState private var refreshTick = 0
    @ViewState private var installError: String?

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
                    // Replaced by the stop-and-ask prompt at the set boundary.
                    .disabled(!autoStart || stopAfterSet)
                Toggle("Stop after each set and ask to continue", isOn: stopAfterSetBinding)
                    .disabled(!autoStart)
            } header: {
                Text("Cycling")
            } footer: {
                Text(cyclingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("Block DNS-over-HTTPS endpoints", isOn: blockDoHBinding)
            } header: {
                Text("Websites")
            } footer: {
                Text("Forces browsers with Secure DNS enabled to fall back to the system resolver, so site blocks aren't bypassed. Disable if you rely on Cloudflare WARP or iCloud Private Relay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)

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
            } header: {
                Text("System")
            } footer: {
                Text("Editing /etc/hosts needs a one-time admin password. Focus installs an /etc/sudoers.d entry so it never has to ask again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        if stopAfterSet {
            return "Runs \(sessions), skips the last break, then asks whether to start another set."
        }
        return "Runs continuously, taking a \(longBreakMinutes) min break after every \(sessions) instead of \(breakMinutes) min."
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

    private var workMinutes: Int { _ = refreshTick; return Defaults.workMinutes }
    private var breakMinutes: Int { _ = refreshTick; return Defaults.breakMinutes }
    private var longBreakMinutes: Int { _ = refreshTick; return Defaults.longBreakMinutes }
    private var sessionsBeforeLongBreak: Int { _ = refreshTick; return Defaults.sessionsBeforeLongBreak }
    private var stopAfterSet: Bool { _ = refreshTick; return Defaults.stopAfterSet }
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
    private var stopAfterSetBinding: Binding<Bool> {
        defaultsBinding(get: { Defaults.stopAfterSet }, set: { Defaults.stopAfterSet = $0 })
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

private struct BlockListTab: View {
    @ViewState private var content: String = ""
    @ViewState private var error: String?
    @ViewState private var loaded = false
    @ViewState private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One site per line. Lines starting with # are comments. www. is added automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .frame(minHeight: 200)

            HStack {
                if let error {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Saved. Changes take effect next time you toggle the block.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            try content.write(to: url, atomically: true, encoding: .utf8)
            // Validate by re-parsing — surfaces invalid hostnames inline.
            _ = try BlockList.load(from: url)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
