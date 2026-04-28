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
            try MusicPresets.resolve(target: "groovesalad", explicitURI: "https://example.com/x")
            == "https://example.com/x"
        )
        // Preset name resolves to its URI.
        #expect(
            try MusicPresets.resolve(target: "dronezone", explicitURI: nil)
            == MusicPresets.uri(for: "dronezone")
        )
        // HTTP(S) stream URLs pass through untouched.
        #expect(
            try MusicPresets.resolve(target: "https://example.com/stream.mp3", explicitURI: nil)
            == "https://example.com/stream.mp3"
        )
        #expect(
            try MusicPresets.resolve(target: "http://radio.example/foo", explicitURI: nil)
            == "http://radio.example/foo"
        )
        // Unknown bare names throw.
        #expect(throws: MusicPresets.ResolveError.self) {
            _ = try MusicPresets.resolve(target: "bogus", explicitURI: nil)
        }
    }

    @Test func resolveRejectsNonHTTPSchemes() {
        // After Spotify removal these should all be treated as unknown presets,
        // not silently passed through to AVPlayer or any handler.
        for unsafe in ["spotify:track:abc", "file:///etc/passwd", "ftp://x.example/y", "javascript:alert(1)"] {
            #expect(throws: MusicPresets.ResolveError.self) {
                _ = try MusicPresets.resolve(target: unsafe, explicitURI: nil)
            }
        }
    }
}
