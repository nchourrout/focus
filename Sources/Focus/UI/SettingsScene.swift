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
        .frame(width: 480, height: 360)
    }
}

private struct GeneralTab: View {
    /// Bumped after SMAppService or sudoers-drop-in state changes, so the
    /// read-only computed properties re-evaluate.
    @State private var refreshTick = 0
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: launchAtLoginBinding) {
                Text("Launch at login")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Pomodoro duration").font(.headline)
                HStack(spacing: 16) {
                    Stepper("Work \(workMinutes) min", value: workBinding, in: 1...180)
                    Stepper("Break \(breakMinutes) min", value: breakBinding, in: 1...60)
                }
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

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var workBinding: Binding<Int> {
        Binding(
            get: { Defaults.workMinutes },
            set: { Defaults.workMinutes = $0; refreshTick += 1 }
        )
    }
    private var breakBinding: Binding<Int> {
        Binding(
            get: { Defaults.breakMinutes },
            set: { Defaults.breakMinutes = $0; refreshTick += 1 }
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
        .onChange(of: content) { _ in save() }
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
