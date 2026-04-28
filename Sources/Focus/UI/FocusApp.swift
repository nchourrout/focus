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

/// Menu bar icon + optional countdown label.
///
/// The per-second countdown is driven by `TimelineView` so its updates stay
/// scoped to a small subtree (otherwise re-renders would also rebuild
/// `MenuContent` and reset AppKit's hover selection).
///
/// Critically: the SF-Symbol `Image` lives OUTSIDE the TimelineView. Earlier
/// the whole HStack was inside, so a fresh `Image(systemName:)` was created
/// each second, which `NSStatusBar.setImage` accumulated without freeing —
/// the app climbed to ~40 GB resident memory and froze. Only the `Text`
/// rebuilds on each tick now.
struct StatusLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let pomodoro = state.pomodoro, state.isRunning {
            HStack(spacing: 4) {
                Image(systemName: state.phase == .break ? "cup.and.saucer.fill" : "timer")
                TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                    let (_, timeLeft) = pomodoro.phase(at: ctx.date.timeIntervalSince1970)
                    Text(formatCountdown(timeLeft)).monospacedDigit()
                }
            }
        } else {
            Image(systemName: state.blockActive ? "nosign" : "circle.dashed")
        }
    }
}
