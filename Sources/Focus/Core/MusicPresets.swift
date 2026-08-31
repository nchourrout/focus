import Foundation

/// The catalogue of curated focus streams, from SomaFM (https://somafm.com) and
/// Radio Paradise (https://radioparadise.com). Both are listener-supported, with
/// no ads and no account required, which is the bar for anything shipped here.
/// Two providers rather than one, so a single outage cannot take the whole
/// catalogue down. AVPlayer drives them in a detached subprocess
/// (`_stream-play`).
///
/// Ordered least eventful first. What makes a station good for focus is mostly
/// what it doesn't do: no vocals, no beat changes, nothing that resolves. The
/// ones further down have more going on, and are here because some people want
/// beats.
///
/// This is the list and its lookups only. What a caller *plays* is a `Station`,
/// which layers meaning (display name, PID-file label, scheme validation) on top.
enum MusicPresets {
    static let list: [(name: String, uri: String)] = [
        ("dronezone",      "https://ice4.somafm.com/dronezone-128-mp3"),       // Ambient drift
        ("darkzone",       "https://ice2.somafm.com/darkzone-256-mp3"),        // Deep ambient, barely moves
        ("deepspaceone",   "https://ice4.somafm.com/deepspaceone-128-mp3"),    // Deep ambient electronic
        ("synphaera",      "https://ice2.somafm.com/synphaera-256-mp3"),       // Modern ambient electronic
        ("serenity",       "https://stream.radioparadise.com/serenity"),       // Radio Paradise ambient
        ("groovesalad",    "https://ice2.somafm.com/groovesalad-128-mp3"),     // Chillout / downtempo
        ("cliqhop",        "https://ice2.somafm.com/cliqhop-128-mp3"),         // Electronic / IDM
        ("missioncontrol", "https://ice2.somafm.com/missioncontrol-128-mp3"),  // NASA / space ambient
    ]

    static func uri(for name: String) -> String? {
        list.first { $0.name == name }?.uri
    }

    /// Reverse lookup, used to recover the preset name when only the stream URL
    /// survived (the daemon and CLI pass resolved URIs around, not preset names).
    static func name(forURI uri: String) -> String? {
        list.first { $0.uri == uri }?.name
    }

    static var names: [String] { list.map { $0.name } }
}
