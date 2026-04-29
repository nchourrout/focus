import Foundation
import UserNotifications

/// Notifications routed through `UNUserNotificationCenter`, which attributes
/// the banner to the calling app's bundle identifier. That's why the user sees
/// the Focus icon here. The daemon (CLI process, no NSApplication) can't use
/// UNC, so phase-change notifications are emitted by `AppState` instead — which
/// observes the same state file the daemon writes.
enum LocalNotifications {
    /// First call shows the system permission prompt; subsequent calls are
    /// no-ops. Safe to invoke from `applicationDidFinishLaunching`.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
