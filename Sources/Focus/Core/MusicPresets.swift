import Foundation

/// Curated focus streams from SomaFM (https://somafm.com) — listener-supported,
/// no ads, no account required. AVPlayer drives them in a detached subprocess
/// (`_stream-play`).
enum MusicPresets {
    static let list: [(name: String, uri: String)] = [
        ("dronezone",      "https://ice4.somafm.com/dronezone-128-mp3"),       // Ambient drift
        ("groovesalad",    "https://ice2.somafm.com/groovesalad-128-mp3"),     // Chillout / downtempo
        ("missioncontrol", "https://ice2.somafm.com/missioncontrol-128-mp3"),  // NASA / space ambient
        ("cliqhop",        "https://ice2.somafm.com/cliqhop-128-mp3"),         // Electronic / IDM
        ("deepspaceone",   "https://ice4.somafm.com/deepspaceone-128-mp3"),    // Deep ambient electronic
    ]

    static func uri(for name: String) -> String? {
        list.first { $0.name == name }?.uri
    }

    static var names: [String] { list.map { $0.name } }

    /// Precedence: explicit URI > target (preset name or http(s):// stream) > FOCUS_MUSIC_URI env.
    /// Returns nil if nothing resolvable; throws if target looks like a preset name but isn't one.
    static func resolve(target: String?, explicitURI: String?) throws -> String? {
        if let uri = explicitURI, !uri.isEmpty { return uri }
        if let t = target, !t.isEmpty {
            if let uri = uri(for: t) { return uri }
            if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
            throw ResolveError.unknownPreset(t)
        }
        let env = ProcessInfo.processInfo.environment["FOCUS_MUSIC_URI"] ?? ""
        return env.isEmpty ? nil : env
    }

    enum ResolveError: Error, LocalizedError {
        case unknownPreset(String)
        var errorDescription: String? {
            switch self {
            case .unknownPreset(let name):
                // No "focus:" prefix — surfaced via ArgumentParser's "Error: …".
                return "unknown preset '\(name)'. Available: \(MusicPresets.names.joined(separator: ", ")). Or pass an http(s):// stream URL."
            }
        }
    }
}
