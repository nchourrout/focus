import Testing
@testable import Focus

@Suite struct MusicPresetsTests {
    @Test func presetLookup() {
        #expect(MusicPresets.uri(for: "deepfocus") != nil)
        #expect(MusicPresets.uri(for: "nope") == nil)
    }

    @Test func resolvePrecedence() throws {
        #expect(
            try MusicPresets.resolve(target: "deepfocus", explicitURI: "spotify:track:X")
            == "spotify:track:X"
        )
        #expect(
            try MusicPresets.resolve(target: "lofi", explicitURI: nil)
            == MusicPresets.uri(for: "lofi")
        )
        #expect(
            try MusicPresets.resolve(target: "spotify:album:Y", explicitURI: nil)
            == "spotify:album:Y"
        )
        #expect(throws: MusicPresets.ResolveError.self) {
            _ = try MusicPresets.resolve(target: "bogus", explicitURI: nil)
        }
    }
}
