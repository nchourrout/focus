import Testing
@testable import Focus

@Suite struct MusicPresetsTests {
    @Test func presetLookup() {
        #expect(MusicPresets.uri(for: "groovesalad") != nil)
        #expect(MusicPresets.uri(for: "nope") == nil)
    }

    @Test func resolvePrecedence() throws {
        // Explicit --uri wins over a preset name.
        #expect(
            try MusicPresets.resolve(target: "groovesalad", explicitURI: "spotify:track:X")
            == "spotify:track:X"
        )
        // Preset name resolves to its URI.
        #expect(
            try MusicPresets.resolve(target: "dronezone", explicitURI: nil)
            == MusicPresets.uri(for: "dronezone")
        )
        // Spotify URIs pass through untouched.
        #expect(
            try MusicPresets.resolve(target: "spotify:album:Y", explicitURI: nil)
            == "spotify:album:Y"
        )
        // HTTP(S) stream URLs pass through untouched.
        #expect(
            try MusicPresets.resolve(target: "https://example.com/stream.mp3", explicitURI: nil)
            == "https://example.com/stream.mp3"
        )
        // Unknown bare names throw.
        #expect(throws: MusicPresets.ResolveError.self) {
            _ = try MusicPresets.resolve(target: "bogus", explicitURI: nil)
        }
    }
}
