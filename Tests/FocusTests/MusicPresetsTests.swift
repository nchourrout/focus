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

    // MARK: Catalogue integrity
    //
    // Both lookups are first-match, and the name doubles as the PID-file label
    // and the UserDefaults value for the pomodoro station, so a duplicate on
    // either side silently makes one entry unreachable. Cheap to guard, and the
    // guard is what a future station addition actually needs.

    @Test func namesAreUniqueAndMenuSafe() {
        let names = MusicPresets.names
        #expect(Set(names).count == names.count)
        for name in names {
            // The name is argv for `focus music <name>` and a PID-file line, so
            // whitespace or an empty string would break parsing either side.
            // Computed outside #expect: the macro's rethrows analysis can't see
            // through a key-path predicate.
            let hasWhitespace = name.contains { $0.isWhitespace }
            #expect(!name.isEmpty)
            #expect(name == name.lowercased())
            #expect(!hasWhitespace)
        }
    }

    @Test func urisAreUniqueAndHTTPS() {
        let uris = MusicPresets.list.map(\.uri)
        #expect(Set(uris).count == uris.count, "name(forURI:) would resolve one of them to the wrong station")
        for preset in MusicPresets.list {
            // Station rejects anything else, so a typo would surface as a preset
            // that silently refuses to play. That it builds a Station at all is
            // asserted in StationTests, over the whole catalogue.
            #expect(preset.uri.hasPrefix("https://"), "\(preset.name) is not https")
        }
    }
}
