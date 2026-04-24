import Foundation

/// Post a macOS user notification. Uses osascript so it works from the detached
/// pomodoro daemon which has no running NSApplication. Phase 2 will add a UI-mode
/// path via UNUserNotificationCenter for richer notifications (action buttons etc.).
enum Notifier {
    static func post(title: String, body: String, sound: String = "Glass") {
        // `body` can be user-supplied (pomodoro goal). Use the sanitizer so a
        // control character doesn't corrupt the AppleScript literal — matches
        // Spotify.play's treatment of URIs.
        guard let t = sanitizeAppleScriptString(title),
              let b = sanitizeAppleScriptString(body),
              let s = sanitizeAppleScriptString(sound) else { return }
        _ = Subprocess.osascript(
            "display notification \"\(b)\" with title \"\(t)\" sound name \"\(s)\""
        )
    }
}
