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
    /// Retained for the length of the cue. An `NSSound` that goes out of scope
    /// can stop partway through, and the delay added below means the sound is
    /// no longer playing by the time `play` returns.
    private static var current: NSSound?
    /// The pending "music back up" hop, cancelled if another cue lands first so
    /// two cues close together duck once rather than fighting each other.
    private static var restore: DispatchWorkItem?

    /// Play the cue for `event`, ducking any focus music underneath it.
    ///
    /// The duck is what makes the cue legible. Without it the cue and a 128 kbps
    /// ambient stream arrive at the same level through the same output, and the
    /// one signal a session actually depends on, that the phase just changed, is
    /// the harder of the two to pick out. Raising the cue is not an option
    /// (`NSSound` plays at system volume, which is already where the user set
    /// it), so the music moves instead.
    static func play(_ event: PhaseSound) {
        guard Defaults.playPhaseSounds else { return }
        guard let cue = event.load() else {
            Log.actions.error("no system sound named \(event.systemName, privacy: .public)")
            return
        }
        current = cue.sound
        restore?.cancel()
        duck(true)

        // Let the duck land before the cue starts. Fired together, the cue's
        // first quarter second, the part that carries its identity, would play
        // under music still at full level.
        DispatchQueue.main.asyncAfter(deadline: .now() + AudioFade.duckDown) {
            cue.sound.play()
        }

        let work = DispatchWorkItem { duck(false) }
        restore = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + AudioFade.duckDown + cue.duration + AudioFade.duckTail,
            execute: work
        )
    }

    /// Off the main thread, because `LocalPlayback.setDucked` reads the music
    /// PID file. It is the same read `AppState.refresh` deliberately pushes into
    /// a detached task so the menu bar never stalls on disk, and a cue fires it
    /// twice.
    private nonisolated static func duck(_ ducked: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            LocalPlayback.setDucked(ducked)
        }
    }
}
