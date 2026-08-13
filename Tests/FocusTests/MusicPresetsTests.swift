import Testing
@testable import Focus

@Suite struct MusicPresetsTests {
    @Test func presetLookup() {
        #expect(MusicPresets.uri(for: "groovesalad") != nil)
        #expect(MusicPresets.uri(for: "nope") == nil)
    }

    // The URI→name round trip is asserted through Station, which is what
    // callers actually use — see StationTests.resolvedURIMapsBackToItsPreset.
    @Test func reverseLookupRejectsUnknownURIs() {
        #expect(MusicPresets.name(forURI: "https://example.com/x") == nil)
    }

}
