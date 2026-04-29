import AppKit

/// Audible phase-transition cues. Plays via `NSSound` (a system-sound by name)
/// rather than relying on `UNUserNotificationCenter`'s built-in alert sound,
/// because macOS Do-Not-Disturb / Focus suppresses notification sounds — and
/// "I'm in a focus session" is exactly when we want the cue audible.
enum PhaseSound {
    case sessionStart  // 0 → work, or break → work (auto-start loop)
    case breakStart    // work → break
    case sessionEnd    // break → done

    /// Built-in macOS sound name (lives under `/System/Library/Sounds/`).
    /// Distinct timbres so the user can tell the events apart by ear.
    var systemName: String {
        switch self {
        case .sessionStart: return "Hero"
        case .breakStart:   return "Glass"
        case .sessionEnd:   return "Submarine"
        }
    }
}

enum Sounds {
    static func play(_ event: PhaseSound) {
        guard Defaults.playPhaseSounds else { return }
        NSSound(named: NSSound.Name(event.systemName))?.play()
    }
}
