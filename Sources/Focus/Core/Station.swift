import Foundation

/// One source of focus audio: a curated preset, an arbitrary http(s) stream, or
/// a local audio file.
///
/// Constructing a Station is the one place a stream's scheme is checked, so
/// nothing downstream re-validates. Every module that used to pass a bare
/// `String` around now passes a Station: the daemon, the CLI, playback, and the
/// menu all read the same value instead of each re-deriving "is this a preset?"
/// from a label.
///
/// Two on-disk encodings, both unchanged from when this was a bare String:
/// `uri` is what the pomodoro state file and `--music` argv carry (a resolved
/// stream URL, wire-compatible with the previous Python tool), and `label` is
/// what the music PID file carries.
enum Station: Equatable {
    /// A name from `MusicPresets.list`. Only built for names known to the catalogue.
    case preset(String)
    /// An http(s) stream that isn't one of the presets.
    case stream(URL)
    /// A local audio file played through `afplay`.
    case file(URL)

    // MARK: Building

    /// A preset by name, or nil if the catalogue doesn't know it.
    init?(preset name: String) {
        guard MusicPresets.uri(for: name) != nil else { return nil }
        self = .preset(name)
    }

    /// Interpret an already-resolved stream URI. A URI that matches a preset
    /// comes back as `.preset` so the menu can show the station name, which is
    /// the round trip the daemon and CLI rely on (they pass resolved URIs, not
    /// preset names). Returns nil for anything that isn't http(s).
    init?(uri: String) {
        if let name = MusicPresets.name(forURI: uri) {
            self = .preset(name)
            return
        }
        guard let url = Self.httpURL(uri) else { return nil }
        self = .stream(url)
    }

    /// Precedence: explicit URI > target (preset name or http(s) URL) > the
    /// `FOCUS_MUSIC_URI` environment variable. Returns nil when nothing is
    /// configured; throws when `target` looks like a preset name but isn't one.
    static func resolve(target: String?, explicitURI: String? = nil) throws -> Station? {
        if let explicitURI, !explicitURI.isEmpty {
            guard let station = Station(uri: explicitURI) else {
                throw ResolveError.notAStream(explicitURI)
            }
            return station
        }
        if let target, !target.isEmpty {
            if let station = Station(preset: target) { return station }
            guard let station = Station(uri: target) else {
                throw ResolveError.unknownPreset(target)
            }
            return station
        }
        let env = ProcessInfo.processInfo.environment["FOCUS_MUSIC_URI"] ?? ""
        guard !env.isEmpty else { return nil }
        guard let station = Station(uri: env) else {
            throw ResolveError.notAStream(env)
        }
        return station
    }

    // MARK: Reading

    /// The stream URL, or the file path. What `--music` argv and the pomodoro
    /// state file carry.
    var uri: String {
        switch self {
        case .preset(let name): return MusicPresets.uri(for: name) ?? name
        case .stream(let url): return url.absoluteString
        case .file(let url): return url.path
        }
    }

    /// Preset name when this is one of the catalogue's stations, else nil.
    /// Drives the checkmark in the music menu.
    var presetName: String? {
        guard case .preset(let name) = self else { return nil }
        return name
    }

    /// Short human label: the preset name capitalized, a custom stream reduced to
    /// its host, a file shown by name.
    var displayName: String {
        switch self {
        case .preset(let name): return name.capitalized
        case .stream(let url): return url.host ?? url.absoluteString
        case .file(let url): return url.lastPathComponent
        }
    }

    // MARK: Music PID file

    /// The music PID file's second line. Same shape it has always had (preset
    /// name, stream URL, or file path), so a PID file written by an older build
    /// still reads back correctly.
    var label: String {
        switch self {
        case .preset(let name): return name
        case .stream(let url): return url.absoluteString
        case .file(let url): return url.path
        }
    }

    /// Parse a music PID file label. Older builds wrote a file's basename rather
    /// than its full path; that still reads back as `.file`, and `displayName` is
    /// the basename either way.
    init?(label: String) {
        guard !label.isEmpty else { return nil }
        if let station = Station(preset: label) {
            self = station
            return
        }
        if let url = Self.httpURL(label) {
            self = .stream(url)
            return
        }
        self = .file(URL(fileURLWithPath: label))
    }

    // MARK: Private

    /// Parse a string as an http(s) URL. The single scheme check the rest of the
    /// codebase used to repeat at four separate hops.
    private static func httpURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    enum ResolveError: Error, LocalizedError {
        case unknownPreset(String)
        case notAStream(String)

        // No "focus:" prefix — surfaced via ArgumentParser's "Error: …".
        var errorDescription: String? {
            switch self {
            case .unknownPreset(let name):
                return "unknown preset '\(name)'. Available: \(MusicPresets.names.joined(separator: ", ")). Or pass an http(s):// stream URL."
            case .notAStream(let uri):
                return "expected an http(s):// stream URL, got: \(uri)"
            }
        }
    }
}
