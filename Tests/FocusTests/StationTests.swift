import Testing
import Foundation
@testable import Focus

@Suite struct StationTests {

    // MARK: Building

    @Test func presetInitRejectsUnknownNames() {
        #expect(Station(preset: "groovesalad") == .preset("groovesalad"))
        #expect(Station(preset: "bogus") == nil)
        #expect(Station(preset: "") == nil)
    }

    @Test func resolvedURIMapsBackToItsPreset() {
        // The daemon and CLI pass resolved URIs around, not preset names, so the
        // menu depends on this round trip to show the station name.
        for preset in MusicPresets.list {
            #expect(Station(uri: preset.uri) == .preset(preset.name))
        }
    }

    @Test func nonPresetStreamsStayStreams() {
        #expect(Station(uri: "https://example.com/x") == .stream(URL(string: "https://example.com/x")!))
        #expect(Station(uri: "http://radio.example/foo") == .stream(URL(string: "http://radio.example/foo")!))
    }

    @Test func nonHTTPURIsAreRejected() {
        // Anything that isn't http(s) must not reach AVPlayer or any URL handler.
        for unsafe in ["file:///etc/passwd", "ftp://x.example/y", "javascript:alert(1)", "not a url"] {
            #expect(Station(uri: unsafe) == nil, "should reject: \(unsafe)")
        }
    }

    // MARK: Resolve

    @Test func resolvePrecedence() throws {
        // A preset name resolves to that preset.
        #expect(try Station.resolve(target: "dronezone") == .preset("dronezone"))
        // Stream URLs come through as streams.
        #expect(
            try Station.resolve(target: "https://example.com/stream.mp3")
            == .stream(URL(string: "https://example.com/stream.mp3")!)
        )
    }

    @Test func resolveRejectsUnknownPresetsAndNonStreams() {
        #expect(throws: Station.ResolveError.self) {
            _ = try Station.resolve(target: "bogus")
        }
        for unsafe in ["file:///etc/passwd", "ftp://x.example/y", "javascript:alert(1)"] {
            #expect(throws: Station.ResolveError.self) {
                _ = try Station.resolve(target: unsafe)
            }
        }
    }

    @Test func streamURLIsNilForFiles() {
        #expect(Station.preset("dronezone").streamURL?.scheme == "https")
        #expect(Station.stream(URL(string: "http://radio.example/x")!).streamURL?.scheme == "http")
        #expect(Station.file(URL(fileURLWithPath: "/tmp/song.mp3")).streamURL == nil)
    }

    // MARK: Reading

    @Test func uriIsTheStreamURLOrFilePath() {
        #expect(Station.preset("dronezone").uri == MusicPresets.uri(for: "dronezone"))
        #expect(Station.stream(URL(string: "https://example.com/x")!).uri == "https://example.com/x")
        #expect(Station.file(URL(fileURLWithPath: "/tmp/song.mp3")).uri == "/tmp/song.mp3")
    }

    @Test func presetNameOnlyForPresets() {
        #expect(Station.preset("cliqhop").presetName == "cliqhop")
        #expect(Station.stream(URL(string: "https://example.com/x")!).presetName == nil)
        #expect(Station.file(URL(fileURLWithPath: "/tmp/song.mp3")).presetName == nil)
    }

    @Test func displayNameIsShortAndHuman() {
        #expect(Station.preset("groovesalad").displayName == "Groovesalad")
        #expect(Station.stream(URL(string: "https://radio.example/a/b.mp3")!).displayName == "radio.example")
        #expect(Station.file(URL(fileURLWithPath: "/tmp/deep/song.mp3")).displayName == "song.mp3")
    }

    // MARK: Music PID file

    @Test func labelRoundTrips() {
        let stations: [Station] = [
            .preset("missioncontrol"),
            .stream(URL(string: "https://radio.example/stream")!),
            .file(URL(fileURLWithPath: "/tmp/song.mp3")),
        ]
        for station in stations {
            #expect(Station(label: station.label) == station, "should round trip: \(station)")
        }
    }

    @Test func labelParsingHandlesOlderPIDFiles() {
        // Older builds wrote a file's basename rather than its full path. It
        // still reads back as a file, and displays the same either way.
        #expect(Station(label: "song.mp3")?.displayName == "song.mp3")
        // And label-less PID files report nothing playing.
        #expect(Station(label: "") == nil)
    }
}
