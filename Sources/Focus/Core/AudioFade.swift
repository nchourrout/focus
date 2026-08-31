import Foundation

/// Timings and levels for every volume ramp Focus performs.
///
/// One place, because two processes have to agree. The menu bar app decides
/// when a duck starts and how long it holds; the detached stream process decides
/// how deep it goes and how fast it gets there. Split across both files, the
/// cue would start before the music had finished moving out of its way.
enum AudioFade {
    /// Silence to playing, when a stream connects. Long enough that the start
    /// of a session is something you notice rather than something that startles.
    static let start: TimeInterval = 2.0

    /// Playing to silence, on a stop request. Short enough that "stop music"
    /// still feels like it happened when you asked.
    static let stop: TimeInterval = 1.2

    /// How far the music drops under a phase cue. 0.25 is 12 dB down: still
    /// audible, clearly behind.
    static let duckLevel: Float = 0.25

    /// Down fast so the cue is never stepped on, back up slowly so the return
    /// is not itself an event worth looking up for.
    static let duckDown: TimeInterval = 0.25
    static let duckUp: TimeInterval = 0.8

    /// Held at the ducked level after the cue ends, before the music comes back.
    static let duckTail: TimeInterval = 0.35
}

/// A volume ramp, evaluated at a point in time. Pure, so the curve is testable
/// without AVFoundation, and so the two callers that drive it (the fade timer
/// and the tests) read the same numbers.
///
/// Interpolates in decibels, not in amplitude. Hearing is roughly logarithmic,
/// so a straight line in amplitude spends most of its length in the loud half
/// and crosses the entire audible tail in its last few percent, which is heard
/// as the hard edge the fade exists to remove. A straight line in dB, which is
/// a geometric sweep in amplitude, changes at an even rate the whole way down.
struct VolumeFade: Equatable {
    /// Volumes as AVPlayer takes them: 0...1, relative to system output.
    var from: Float
    var to: Float
    var duration: TimeInterval

    /// How far below the loud endpoint the sweep starts or stops when the other
    /// endpoint is silence. Silence has no decibel value, so the ramp runs to
    /// this floor and then snaps the rest of the way. 40 dB down is inaudible
    /// under anything, so the snap is not a click.
    private static let floorDB: Float = 40

    /// Volume `elapsed` seconds in. Clamped at both ends: before the ramp starts
    /// it reads exactly `from`, at or after it finishes exactly `to`.
    func volume(atElapsed elapsed: TimeInterval) -> Float {
        guard duration > 0 else { return to }
        let progress = elapsed / duration
        if progress <= 0 { return from }
        if progress >= 1 { return to }

        let loudest = max(from, to)
        // A ramp from silence to silence has no dB range to sweep.
        guard loudest > 0 else { return 0 }
        // `max` covers both jobs at once: it substitutes the floor for a silent
        // endpoint, and keeps an endpoint quieter than the floor from inverting
        // the sweep.
        let floor = loudest * pow(10, -Self.floorDB / 20)
        let start = max(from, floor)
        let end = max(to, floor)
        return start * pow(end / start, Float(progress))
    }
}
