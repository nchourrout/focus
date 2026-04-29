import Foundation

/// Escape `\` and `"` so a user-supplied string can be safely interpolated into
/// an AppleScript double-quoted string literal.
func escapeAppleScript(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
}

/// Like `escapeAppleScript` but returns nil if the input contains newlines or
/// other control characters that would break the string literal even after
/// escaping. Used wherever user-controlled text is interpolated into an
/// AppleScript command (sudoers admin dialog, etc.).
func sanitizeAppleScriptString(_ s: String) -> String? {
    guard s.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
    return escapeAppleScript(s)
}
