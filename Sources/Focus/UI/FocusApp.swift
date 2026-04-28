import SwiftUI

struct FocusApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(FocusAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            StatusLabel(state: state)
        }
        .menuBarExtraStyle(.menu)

        // A standalone Window (instead of the Settings scene) — the standard
        // Settings scene's window doesn't reliably show for LSUIElement menu
        // bar apps; openWindow(id:) works.
        Window("Focus Settings", id: "settings") {
            SettingsContent()
        }
        .windowResizability(.contentSize)
    }
}

/// NSApp is only guaranteed wired up once the app has launched, so activation-
/// policy and hotkey-registration side effects live here rather than in init().
final class FocusAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HotKeys.registerAll()
    }
}

/// Menu bar icon + optional countdown label. Updates every tick via AppState.
struct StatusLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.isRunning {
            Label {
                Text(formatCountdown(state.timeLeft))
            } icon: {
                Image(systemName: state.phase == .break ? "cup.and.saucer.fill" : "timer")
            }
        } else {
            Image(systemName: state.blockActive ? "nosign" : "circle.dashed")
        }
    }
}
