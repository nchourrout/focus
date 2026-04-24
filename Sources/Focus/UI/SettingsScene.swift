import SwiftUI
import KeyboardShortcuts

struct SettingsContent: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 440, height: 260)
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
            KeyboardShortcuts.Recorder("Start pomodoro", name: .startPomodoro)
            KeyboardShortcuts.Recorder("Stop pomodoro", name: .stopPomodoro)
            KeyboardShortcuts.Recorder("Toggle website block", name: .toggleBlock)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
