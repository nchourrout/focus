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
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                LaunchAtLogin.set(newValue)
                launchAtLogin = LaunchAtLogin.isEnabled
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
