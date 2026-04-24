import Foundation

enum Spotify {
    /// Open Spotify if needed, then play a URI (playlist, album, track).
    /// Returns true on success. URIs with control characters are rejected.
    @discardableResult
    static func play(uri: String) -> Bool {
        guard let safe = sanitizeAppleScriptString(uri) else { return false }
        _ = Subprocess.osascript("tell application \"Spotify\" to activate")
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

/// Like `escapeAppleScript` but returns nil if the input contains newlines or
/// other control characters that would break the string literal even after
/// escaping. Safer for URIs sourced from user input.
func sanitizeAppleScriptString(_ s: String) -> String? {
    guard s.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
    return escapeAppleScript(s)
}
