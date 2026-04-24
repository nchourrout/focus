import Foundation

enum Spotify {
    /// Open Spotify if needed, then play a URI (playlist, album, track).
    /// Returns true on success.
    @discardableResult
    static func play(uri: String) -> Bool {
        _ = Subprocess.osascript("tell application \"Spotify\" to activate")
        let safe = escapeAppleScript(uri)
        return Subprocess.osascript("tell application \"Spotify\" to play track \"\(safe)\"") == 0
    }

    static func pause() {
        _ = Subprocess.osascript("tell application \"Spotify\" to pause")
    }
}

/// Escape `\` and `"` so a user-supplied string can be safely interpolated into
/// an AppleScript double-quoted string literal.
func escapeAppleScript(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
}
