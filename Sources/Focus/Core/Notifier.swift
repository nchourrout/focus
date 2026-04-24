import Foundation

/// Post a macOS user notification. Uses osascript so it works from the detached
/// pomodoro daemon which has no running NSApplication. Phase 2 will add a UI-mode
/// path via UNUserNotificationCenter for richer notifications (action buttons etc.).
enum Notifier {
    static func post(title: String, body: String, sound: String = "Glass") {
        let t = escapeAppleScript(title)
        let b = escapeAppleScript(body)
        let s = escapeAppleScript(sound)
        _ = Subprocess.osascript(
            "display notification \"\(b)\" with title \"\(t)\" sound name \"\(s)\""
        )
    }
}
