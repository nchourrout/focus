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
    }
}

/// NSApp is only guaranteed wired up once the app has launched, so the activation
/// policy switch lives here rather than in FocusApp.init().
final class FocusAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Menu bar icon + optional countdown label. Updates every tick via AppState.
struct StatusLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.pomodoro != nil, state.phase != .done {
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
