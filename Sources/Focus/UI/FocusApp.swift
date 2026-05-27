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
        LocalNotifications.requestAuthorization()
    }
}

/// Menu bar icon + optional countdown label.
///
/// The countdown lives in `CountdownText`, a child view that owns its own
/// 1Hz timer. Driving the tick from inside that subview means:
///   (1) MenuBarExtra picks up the per-second updates (TimelineView ticks
///       don't always propagate to the menu bar label snapshot on macOS 15+);
///   (2) MenuContent's @ObservedObject doesn't see a change, so AppKit's
///       hover selection doesn't reset every second;
///   (3) the SF-Symbol `Image` lives in the parent body and isn't recreated
///       per tick — past attempt to do so leaked NSImage refs through
///       NSStatusBar.setImage, climbing to ~40 GB resident memory.
struct StatusLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let pomodoro = state.pomodoro, state.isRunning {
            HStack(spacing: 4) {
                Image(systemName: state.phase == .break ? "cup.and.saucer.fill" : "timer")
                CountdownText(pomodoro: pomodoro)
            }
        } else {
            Image(systemName: state.blockActive ? "nosign" : "circle.dashed")
        }
    }
}

private struct CountdownText: View {
    let pomodoro: PomodoroSession.Active
    @State private var now: Date = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let (_, timeLeft) = PomodoroSession.default.phase(of: pomodoro, at: now.timeIntervalSince1970)
        Text(formatCountdown(timeLeft))
            .monospacedDigit()
            .onReceive(tick) { now = $0 }
    }
}
