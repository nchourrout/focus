import ArgumentParser
import Foundation

struct Music: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "music",
        abstract: "play or stop focus music"
    )

    @Argument(help: "Preset name (see --list) or an http(s):// stream URL")
    var target: String?

    @Option(help: "Stream URL (overrides target / FOCUS_MUSIC_URI)")
    var uri: String?

    @Option(help: "Local audio file to play with afplay")
    var file: String?

    @Flag(help: "Loop the local file")
    var loop: Bool = false

    @Flag(help: "Stop any current playback")
    var stop: Bool = false

    @Flag(name: .customLong("list"), help: "Show available presets")
    var list: Bool = false

    func run() throws {
        if list {
            let width = MusicPresets.list.map { $0.name.count }.max() ?? 0
            for p in MusicPresets.list {
                let pad = String(repeating: " ", count: width - p.name.count)
                print("  \(p.name)\(pad)  \(p.uri)")
            }
            return
        }

        if stop {
            LocalPlayback.stop()
            print("focus: music stopped")
            return
        }

        if let filePath = file {
            let url = try resolveExistingFile(filePath)
            try LocalPlayback.play(.file(url), loop: loop)
            print("focus: playing \(url.path)" + (loop ? " (looped)" : ""))
            return
        }

        // An explicit --uri is already a URL, so it skips the resolver's
        // preset-name-or-environment precedence and goes straight to a Station.
        let station: Station
        if let uri, !uri.isEmpty {
            guard let explicit = Station(uri: uri) else {
                throw Station.ResolveError.notAStream(uri)
            }
            station = explicit
        } else {
            guard let resolved = try Station.resolve(target: target) else {
                throw CLIError.missingMusicSource
            }
            station = resolved
        }
        try LocalPlayback.play(station)
        print("focus: streaming \(station.uri)")
    }
}

/// Hidden: subprocess that plays an HTTP audio stream via AVPlayer.
struct StreamPlay: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "_stream-play",
        shouldDisplay: false
    )

    @Option(help: "HTTP audio stream URL to play.")
    var url: String

    func run() {
        StreamPlayer.run(url: url)
    }
}

/// Hidden: inner loop process started by `music --file --loop`.
struct AfplayLoop: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "_afplay-loop",
        shouldDisplay: false
    )

    @Option(help: "Audio file to play in a loop.")
    var file: String

    func run() {
        LocalPlayback.runAfplayLoop(file: file)
    }
}
