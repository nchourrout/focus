import Foundation

/// The catalogue of curated focus streams from SomaFM (https://somafm.com) —
/// listener-supported, no ads, no account required. AVPlayer drives them in a
/// detached subprocess (`_stream-play`).
///
/// This is the list and its lookups only. What a caller *plays* is a `Station`,
/// which layers meaning (display name, PID-file label, scheme validation) on top.
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

    /// Reverse lookup, used to recover the preset name when only the stream URL
    /// survived (the daemon and CLI pass resolved URIs around, not preset names).
    static func name(forURI uri: String) -> String? {
        list.first { $0.uri == uri }?.name
    }

    static var names: [String] { list.map { $0.name } }
}
