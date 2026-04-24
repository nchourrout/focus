import Foundation

/// Curated focus playlists. Edit to taste; later phases move this to user-editable config.
enum MusicPresets {
    static let list: [(name: String, uri: String)] = [
        ("deepfocus", "spotify:playlist:37i9dQZF1DX0XUsuxWHRQd"),  // Deep Focus
        ("piano",     "spotify:playlist:37i9dQZF1DX4sWSpwq3LiO"),  // Peaceful Piano
        ("lofi",      "spotify:playlist:37i9dQZF1DWWQRwui0ExPn"),  // Lofi Beats
        ("intense",   "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"),  // Intense Studying
        ("ambient",   "spotify:playlist:37i9dQZF1DX3Ogo9pFvBkY"),  // Ambient Relaxation
    ]

    static func uri(for name: String) -> String? {
        list.first { $0.name == name }?.uri
    }

    static var names: [String] { list.map { $0.name } }

    /// Precedence: explicit URI > target (preset name or raw spotify: URI) > FOCUS_SPOTIFY_URI env.
    /// Returns nil if nothing resolvable; throws if target looks like a preset name but isn't one.
    static func resolve(target: String?, explicitURI: String?) throws -> String? {
        if let uri = explicitURI, !uri.isEmpty { return uri }
        if let t = target, !t.isEmpty {
            if let uri = uri(for: t) { return uri }
            if t.hasPrefix("spotify:") { return t }
            throw ResolveError.unknownPreset(t)
        }
        let env = ProcessInfo.processInfo.environment["FOCUS_SPOTIFY_URI"] ?? ""
        return env.isEmpty ? nil : env
    }

    enum ResolveError: Error, LocalizedError {
        case unknownPreset(String)
        var errorDescription: String? {
            switch self {
            case .unknownPreset(let name):
                return "focus: unknown preset '\(name)'. Available: \(MusicPresets.names.joined(separator: ", ")). Or pass a spotify:... URI."
            }
        }
    }
}
