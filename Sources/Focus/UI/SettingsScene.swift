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
    /// Trigger to force SwiftUI re-evaluation after SMAppService state changes.
    @State private var refreshTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: launchAtLoginBinding) {
                Text("Launch at login")
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
