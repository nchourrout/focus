import SwiftUI
import UserNotifications
import os

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
final class FocusAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HotKeys.registerAll()
        // Become the notification delegate before registering categories so the
        // "Start another set" action routes back here. Categories must be set up
        // before any set-complete notification could fire.
        UNUserNotificationCenter.current().delegate = self
        LocalNotifications.registerCategories()
        LocalNotifications.requestAuthorization()
    }

    /// Show banners even when Focus is the frontmost app (e.g. Settings open).
    /// Without an explicit handler, a foreground app suppresses its own banners.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Handle the set-complete actions. "Start another set" reuses the previous
    /// goal; "New goal…" starts the next set with the typed text (falling back to
    /// the previous goal if the field was submitted empty). Both relaunch with the
    /// user's current settings. Other responses (default tap, dismiss) do nothing.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let previousGoal = response.notification.request.content
            .userInfo[LocalNotifications.goalUserInfoKey] as? String

        let goal: String?
        switch response.actionIdentifier {
        case LocalNotifications.startAnotherSetAction:
            goal = previousGoal
        case LocalNotifications.newGoalAction:
            let typed = (response as? UNTextInputNotificationResponse)?
                .userText.trimmingCharacters(in: .whitespacesAndNewlines)
            goal = (typed?.isEmpty == false) ? typed : previousGoal
        default:
            goal = nil
        }

        // `goal` is already non-empty when set: previousGoal comes from a live
        // session (goals can't be empty) and the typed branch falls back to it.
        if let goal {
            Task { @MainActor in Actions.startPomodoro(goal: goal) }
        }
        completionHandler()
    }

    /// Cleanly tear down anything that would otherwise outlive the menu bar app:
    /// a running pomodoro daemon (it handles its own block/music cleanup based on
    /// the session's `block` flag) and a standalone /etc/hosts block left active
    /// by a manual toggle. Both calls are synchronous; macOS gives apps several
    /// seconds during termination.
    ///
    /// If the sudoers drop-in is missing, the unblock can't run — we log to
    /// Unified Logging instead of silently leaving the user blocked without a
    /// trace. The block will lift the next time they grant permission and
    /// toggle.
    func applicationWillTerminate(_ notification: Notification) {
        if PomodoroSession.default.current != nil {
            PomodoroDaemon.stop()
        }
        if SiteBlock.default.isActive {
            guard SudoersInstaller.isInstalled else {
                Logger(subsystem: "com.nchourrout.focus", category: "terminate")
                    .warning("block still active on quit; sudoers drop-in missing, leaving /etc/hosts as-is")
                return
            }
            let result = Shell.run(Shell.Command(Paths.selfExecutable, ["unblock"], sudo: true))
            if result.status != 0 {
                Logger(subsystem: "com.nchourrout.focus", category: "terminate")
                    .error("unblock-on-quit failed (status \(result.status, privacy: .public))")
            }
        }
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
