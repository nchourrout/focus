import Foundation
import AVFoundation
import Darwin

/// HTTP audio stream player driven by AVPlayer. Mirrors `LocalPlayback.runAfplayLoop`
/// but for network streams instead of local files. Runs in a detached subprocess
/// (`_stream-play`) so the menu bar app and CLI use the same kill-by-PID stop path
/// as afplay.
enum StreamPlayer {
    /// Body of the hidden `_stream-play` subcommand. Streams forever until SIGTERM
    /// (default termination kills AVPlayer's audio session implicitly).
    static func run(url: String) {
        // Own session/process group so the menu bar app's killpg cleanly stops us.
        _ = setsid()

        guard let streamURL = URL(string: url) else { exit(1) }

        let player = AVPlayer(url: streamURL)
        player.automaticallyWaitsToMinimizeStalling = true
        player.play()
        // Block on the run loop; SIGTERM terminates the process and AVPlayer with it.
        RunLoop.current.run()
    }
}
