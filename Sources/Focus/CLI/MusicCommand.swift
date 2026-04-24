import ArgumentParser
import Foundation

struct Music: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "music",
        abstract: "play or stop focus music"
    )

    @Argument(help: "Preset name (see --list) or a spotify: URI")
    var target: String?

    @Option(help: "Spotify URI (overrides target / FOCUS_SPOTIFY_URI)")
    var uri: String?

    @Option(help: "Local audio file to play with afplay")
    var file: String?

    @Flag(help: "Loop the local file")
    var loop: Bool = false

    @Flag(help: "Pause Spotify and stop afplay")
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
            Spotify.pause()
            LocalPlayback.stop()
            print("focus: music stopped")
            return
        }

        if let filePath = file {
            let url = URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath)
            if !FileManager.default.fileExists(atPath: url.path) {
                throw CLIError.missingFile(url)
            }
            try LocalPlayback.start(path: url, loop: loop)
            print("focus: playing \(url.path)" + (loop ? " (looped)" : ""))
            return
        }

        guard let resolved = try MusicPresets.resolve(target: target, explicitURI: uri) else {
            throw CLIError.missingMusicSource
        }
        if Spotify.play(uri: resolved) {
            print("focus: playing \(resolved)")
        } else {
            FocusCLI.exit(withError: ExitCode(1))
        }
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
