import AppKit

/// Audible phase-transition cues. Plays via `NSSound` (a system-sound by name)
/// rather than relying on `UNUserNotificationCenter`'s built-in alert sound,
/// because macOS Do-Not-Disturb / Focus suppresses notification sounds, and
/// "I'm in a focus session" is exactly when we want the cue audible.
enum PhaseSound {
    case sessionStart  // 0 to work, or break to work (auto-start loop)
    case breakStart    // work to break
    case sessionEnd    // break to done

    /// Built-in macOS sound name (lives under `/System/Library/Sounds/`).
    /// Distinct timbres so the user can tell the events apart by ear.
    var systemName: String {
        switch self {
        case .sessionStart: return "Hero"
        case .breakStart:   return "Glass"
        case .sessionEnd:   return "Submarine"
        }
    }

    /// The cue and how long it runs, or nil if the name doesn't resolve.
    ///
    /// The length is needed to know when the music may come back up, and
    /// `NSSound.duration` reads 0 for a sound it has no length for, so both the
    /// lookup and its fallback live here rather than at the call site.
    func load() -> (sound: NSSound, duration: TimeInterval)? {
        guard let sound = NSSound(named: NSSound.Name(systemName)) else { return nil }
        return (sound, sound.duration > 0 ? sound.duration : Self.assumedDuration)
    }

    /// Comfortably covers every cue in /System/Library/Sounds.
    private static let assumedDuration: TimeInterval = 1.5
}

@MainActor
enum Sounds {
    /// Play the cue for `event`, ducking any focus music underneath it.
    ///
    /// The duck is what makes the cue legible. Without it the cue and a 128 kbps
    /// ambient stream arrive at the same level through the same output, and the
    /// one signal a session actually depends on, that the phase just changed, is
    /// the harder of the two to pick out. Raising the cue is not an option
    /// (`NSSound` plays at system volume, which is already where the user set
    /// it), so the music moves instead. `LocalPlayback` owns the ramp either
    /// side; the only part that belongs here is when the cue starts and how long
    /// the music has to stay down for it.
    static func play(_ event: PhaseSound) {
        guard Defaults.playPhaseSounds else { return }
        guard let cue = event.load() else {
            Log.actions.error("no system sound named \(event.systemName, privacy: .public)")
            return
        }

        // No music to duck means nothing to wait for. Delaying the cue anyway
        // would push it a quarter second off the banner it accompanies for every
        // user who runs sessions without music.
        let target = LocalPlayback.duckable
        let delay = target == nil ? 0 : AudioFade.duckDown
        if let target {
            // Down before the cue starts, up a beat after it ends. Fired
            // together, the cue's first quarter second, the part that carries
            // its identity, would play under music still at full level.
            LocalPlayback.duck(target, for: delay + cue.duration + AudioFade.duckTail)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            cue.sound.play()
        }
        // An `NSSound` released mid-cue can stop partway through, and `play`
        // returns long before this one is done. This block is the only thing
        // holding it, which also means two overlapping cues each keep their own.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + cue.duration) {
            withExtendedLifetime(cue.sound) {}
        }
    }
}
