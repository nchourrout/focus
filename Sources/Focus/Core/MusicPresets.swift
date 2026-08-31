import Foundation

/// The catalogue of curated focus streams, all from SomaFM (https://somafm.com):
/// listener-supported, no ads, no account required. AVPlayer drives them in a
/// detached subprocess (`_stream-play`).
///
/// One provider is a known weakness, and two candidates were tried and rejected
/// rather than not looked for. Radio Paradise serves its ambient channel only as
/// raw ADTS AAC or Ogg FLAC, and Ambient Sleeping Pill as HTTP/1.0 Icecast:
/// AVPlayer connects to both, pulls them at full bitrate, and decodes neither.
/// A station is only shippable here if AVPlayer actually renders it, which
/// process liveness does not show. See CONTRIBUTING notes in the README.
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
