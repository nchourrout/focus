import Foundation
import AppKit

enum Spotify {
    /// What `play(uri:)` actually accomplished. Track URIs get true playback;
    /// playlists/albums can only be navigated to (Spotify's AppleScript can't
    /// switch playback context to a non-track URI, and we don't have OAuth).
    enum Outcome {
        case playing       // Spotify is playing the requested track.
        case opened        // Navigated Spotify to the playlist/album; user must press Play.
        case failed
    }

    /// Activate Spotify on a URI.
    ///
    /// - Track URIs (`spotify:track:...`) start playback via AppleScript's
    ///   `play track <uri>`.
    /// - Playlist / album URIs are routed through Spotify's URL handler, which
    ///   navigates the app to the requested view but cannot start playback
    ///   without a track URI in the queue. The user presses Play (or spacebar)
    ///   to start the playlist. This is a Spotify limitation, not ours.
    @discardableResult
    static func play(uri: String) -> Outcome {
        guard let safe = sanitizeAppleScriptString(uri),
              let url = URL(string: uri) else { return .failed }

        if uri.hasPrefix("spotify:track:") {
            _ = Subprocess.osascript("tell application \"Spotify\" to activate")
            let rc = Subprocess.osascript("tell application \"Spotify\" to play track \"\(safe)\"")
            return rc == 0 ? .playing : .failed
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let sem = DispatchSemaphore(value: 0)
        var opened = false
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            opened = (error == nil)
            sem.signal()
        }
        sem.wait()
        return opened ? .opened : .failed
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
