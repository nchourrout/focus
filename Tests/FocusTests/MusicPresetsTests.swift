import Testing
@testable import Focus

@Suite struct MusicPresetsTests {
    @Test func presetLookup() {
        #expect(MusicPresets.uri(for: "groovesalad") != nil)
        #expect(MusicPresets.uri(for: "nope") == nil)
    }

    @Test func reverseLookupRoundTrips() {
        // Every preset URI maps back to its name — the menu bar relies on this
        // to recover the station name from the resolved stream URL.
        for preset in MusicPresets.list {
            #expect(MusicPresets.name(forURI: preset.uri) == preset.name)
        }
        #expect(MusicPresets.name(forURI: "https://example.com/x") == nil)
    }

}
