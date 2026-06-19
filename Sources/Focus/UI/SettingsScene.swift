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
        .frame(width: 480, height: 460)
    }
}

private struct GeneralTab: View {
    /// Bumped after SMAppService or sudoers-drop-in state changes, so the
    /// read-only computed properties re-evaluate.
    @State private var refreshTick = 0
    @State private var installError: String?

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: launchAtLoginBinding) {
                Text("Launch at login")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Pomodoro").font(.headline)
                HStack(spacing: 16) {
                    Stepper("Work \(workMinutes) min", value: workBinding, in: 1...180)
                    Stepper("Break \(breakMinutes) min", value: breakBinding, in: 1...60)
                }
                Toggle(isOn: blockDuringPomodoroBinding) {
                    Text("Block websites during pomodoro")
                }
                Toggle(isOn: autoStartBinding) {
                    Text("Keep cycling sessions until I stop")
                }
                HStack(spacing: 16) {
                    Stepper("Long break \(longBreakMinutes) min", value: longBreakBinding, in: 1...60)
                    Stepper("after every \(sessionsBeforeLongBreak)", value: sessionsBinding, in: 1...12)
                }
                .disabled(!Defaults.autoStartNextSession)
                Toggle(isOn: phaseSoundsBinding) {
                    Text("Play sound at phase transitions")
                }
                Picker("Start music with pomodoro", selection: pomodoroMusicBinding) {
                    Text("None").tag("")
                    ForEach(MusicPresets.list, id: \.name) { preset in
                        Text(preset.name.capitalized).tag(preset.name)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: blockDoHBinding) {
                    Text("Block DNS-over-HTTPS endpoints")
                }
                Text("Forces browsers with Secure DNS enabled to fall back to the system resolver, so site blocks aren't bypassed. Disable if you rely on Cloudflare WARP or iCloud Private Relay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: permissionInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(permissionInstalled ? .green : .orange)
                    Text(permissionInstalled ? "System permission: granted" : "System permission: not granted")
                }
                Text("Focus needs a one-time admin password to install a `/etc/sudoers.d` entry allowing it to edit /etc/hosts without prompting on every toggle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(permissionInstalled ? "Reinstall permission…" : "Grant permission…") {
                    installPermission()
                }
            }

            if let installError = installError {
                Text(installError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var permissionInstalled: Bool {
        _ = refreshTick
        return SudoersInstaller.isInstalled
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
    private var pomodoroMusicBinding: Binding<String> {
        defaultsBinding(get: { Defaults.pomodoroMusic }, set: { Defaults.pomodoroMusic = $0 })
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
        VStack(alignment: .leading, spacing: 12) {
            KeyboardShortcuts.Recorder("Start / stop pomodoro", name: .togglePomodoro)
            KeyboardShortcuts.Recorder("Toggle website block", name: .toggleBlock)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct BlockListTab: View {
    @State private var content: String = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

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
