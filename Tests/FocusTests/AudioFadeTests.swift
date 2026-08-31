import Testing
import Foundation
@testable import Focus

/// The fade curve. Everything the ear notices about a ramp is in these numbers,
/// and none of it is reachable from a test once it's inside an AVPlayer.
@Suite struct VolumeFadeTests {

    /// dB below the loud end at a given point on the ramp, which is the unit the
    /// curve is actually specified in.
    private func decibels(_ volume: Float, under loudest: Float = 1) -> Float {
        20 * log10(volume / loudest)
    }

    // MARK: Endpoints

    @Test func startsAtFromAndEndsExactlyAtTo() {
        let fade = VolumeFade(from: 0, to: 1, duration: 2)
        #expect(fade.volume(atElapsed: 0) == 0)
        #expect(fade.volume(atElapsed: 2) == 1)
    }

    @Test func clampsOutsideItsWindow() {
        let fade = VolumeFade(from: 1, to: 0, duration: 1.2)
        #expect(fade.volume(atElapsed: -5) == 1)
        #expect(fade.volume(atElapsed: 99) == 0, "a fade-out must reach real silence, not the floor")
    }

    @Test func aZeroLengthFadeIsJustTheDestination() {
        #expect(VolumeFade(from: 0, to: 1, duration: 0).volume(atElapsed: 0) == 1)
    }

    // MARK: The curve itself

    /// The whole reason this isn't a straight line in amplitude: equal slices of
    /// the ramp are equal steps in dB, so the midpoint sits 20 dB down rather
    /// than at half the amplitude, which is only 6 dB down and still plainly loud.
    @Test func equalTimeStepsAreEqualDecibelSteps() {
        let fade = VolumeFade(from: 1, to: 0, duration: 4)
        let steps = (1...4).map { decibels(fade.volume(atElapsed: TimeInterval($0))) }
        // -10, -20, -30, then the snap to silence at the end.
        #expect(abs(steps[0] - -10) < 0.01)
        #expect(abs(steps[1] - -20) < 0.01)
        #expect(abs(steps[2] - -30) < 0.01)
        #expect(fade.volume(atElapsed: 4) == 0)
        #expect(fade.volume(atElapsed: 2) < 0.5, "a linear-amplitude ramp would sit at 0.5 here")
    }

    @Test func theFloorSetsWhereTheSweepBegins() {
        // Just past the start, a fade in from silence sits at the floor.
        let fade = VolumeFade(from: 0, to: 1, duration: 2)
        #expect(abs(decibels(fade.volume(atElapsed: 0.0001)) - -40) < 0.1)
    }

    @Test func fadeInAndFadeOutAreMirrorImages() {
        let up = VolumeFade(from: 0, to: 1, duration: 2)
        let down = VolumeFade(from: 1, to: 0, duration: 2)
        for t in stride(from: 0.2, through: 1.8, by: 0.2) {
            #expect(abs(up.volume(atElapsed: t) - down.volume(atElapsed: 2 - t)) < 0.0001)
        }
    }

    // MARK: Ducking, where neither endpoint is silence

    @Test func aDuckSweepsBetweenTwoAudibleLevels() {
        let duck = VolumeFade(from: 1, to: AudioFade.duckLevel, duration: AudioFade.duckDown)
        #expect(duck.volume(atElapsed: 0) == 1)
        #expect(duck.volume(atElapsed: AudioFade.duckDown) == AudioFade.duckLevel)
        // Halfway down the duck is halfway down the range it spans, not halfway
        // down the amplitude.
        let half = duck.volume(atElapsed: AudioFade.duckDown / 2)
        #expect(abs(decibels(half) - decibels(AudioFade.duckLevel) / 2) < 0.01)
        #expect(half < (1 + AudioFade.duckLevel) / 2,
                "a linear-amplitude duck would still be sitting at 0.625 here")
    }

    @Test func aFadeIsMonotonicInBothDirections() {
        let up = VolumeFade(from: AudioFade.duckLevel, to: 1, duration: AudioFade.duckUp)
        let down = VolumeFade(from: 1, to: 0, duration: AudioFade.stop)
        var previousUp = up.volume(atElapsed: 0)
        var previousDown = down.volume(atElapsed: 0)
        for step in 1...50 {
            let t = TimeInterval(step) / 50
            let nowUp = up.volume(atElapsed: t * AudioFade.duckUp)
            let nowDown = down.volume(atElapsed: t * AudioFade.stop)
            #expect(nowUp >= previousUp)
            #expect(nowDown <= previousDown)
            previousUp = nowUp
            previousDown = nowDown
        }
    }

    // MARK: Degenerate inputs

    @Test func silenceToSilenceStaysSilent() {
        let fade = VolumeFade(from: 0, to: 0, duration: 1)
        #expect(fade.volume(atElapsed: 0.5) == 0, "no dB range to sweep, and no NaN either")
    }

    @Test func neverLeavesTheVolumeRange() {
        for fade in [VolumeFade(from: 0, to: 1, duration: 2),
                     VolumeFade(from: 1, to: 0, duration: 1.2),
                     VolumeFade(from: 1, to: 0.25, duration: 0.25),
                     VolumeFade(from: 0.25, to: 1, duration: 0.8)] {
            for step in 0...40 {
                let v = fade.volume(atElapsed: fade.duration * TimeInterval(step) / 40)
                #expect(v >= 0 && v <= 1)
                #expect(!v.isNaN)
            }
        }
    }
}

/// The constants two processes have to agree on, pinned to the properties that
/// make them work rather than to their exact values.
@Suite struct AudioFadeConstantsTests {

    @Test func theDuckIsAudibleButClearlyBehind() {
        let dB = 20 * log10(AudioFade.duckLevel)
        #expect(dB < -6, "not enough to make room for the cue")
        #expect(dB > -20, "so far down the music may as well have stopped")
    }

    @Test func theDuckDropsFasterThanItReturns() {
        #expect(AudioFade.duckDown < AudioFade.duckUp)
    }

    @Test func stoppingIsQuickerThanStarting() {
        // Starting can afford to be gentle; "stop music" has to feel like it
        // happened when you asked.
        #expect(AudioFade.stop < AudioFade.start)
    }
}
