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
    /// Cues still sounding. An `NSSound` that goes out of scope can stop partway
    /// through, and one slot is not enough: `AppState` can emit a recovery cue
    /// and a transition cue from the same tick, and the second would drop the
    /// first's only reference.
    private static var sounding: [NSSound] = []
    /// The pending "music back up" hop, cancelled if another cue lands first so
    /// two cues close together duck once rather than fighting each other.
    private static var restore: DispatchWorkItem?
    /// Serial, so a duck can never be overtaken by the restore that follows it.
    /// On a concurrent queue those two are unordered, and losing that race
    /// leaves the music 12 dB down with nothing scheduled to lift it.
    /// `nonisolated` because `duck` is: it touches nothing on the main actor.
    private nonisolated static let controlQueue = DispatchQueue(label: "focus.sounds.duck")

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
        sounding.append(cue.sound)
        restore?.cancel()

        // Resolved once, and held: the restore has to reach the process that was
        // ducked. Re-reading the PID file when the cue ends would find whatever
        // is playing by then, and un-ducking a station the user switched to
        // mid-cue would cut its 2s fade-in down to a 0.8s one.
        let target = LocalPlayback.duckable
        // Nothing to duck means nothing to wait for. Delaying the cue anyway
        // would push it a quarter second off the banner it accompanies for every
        // user who runs sessions without music.
        let delay = target == nil ? 0 : AudioFade.duckDown
        if let target {
            duck(true, on: target)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { cue.sound.play() }
        } else {
            cue.sound.play()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + cue.duration) {
            sounding.removeAll { $0 === cue.sound }
        }
        guard let target else { return }
        let work = DispatchWorkItem { duck(false, on: target) }
        restore = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay + cue.duration + AudioFade.duckTail,
            execute: work
        )
    }

    /// Off the main thread, because `LocalPlayback.setDucked` probes the tracked
    /// process. It is the same class of work `AppState.refresh` deliberately
    /// pushes into a detached task so the menu bar never stalls on it.
    private nonisolated static func duck(_ ducked: Bool, on target: LocalPlayback.Duckable) {
        controlQueue.async { LocalPlayback.setDucked(ducked, on: target) }
    }
}
