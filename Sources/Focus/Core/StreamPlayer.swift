import Foundation
import AVFoundation
import Darwin

/// HTTP audio stream player driven by AVPlayer. Mirrors `LocalPlayback.runAfplayLoop`
/// but for network streams instead of local files. Runs in a detached subprocess
/// (`_stream-play`) so the menu bar app and CLI use the same kill-by-PID stop path
/// as afplay.
enum StreamPlayer {
    /// Body of the hidden `_stream-play` subcommand. Streams forever until SIGTERM
    /// or until AVPlayer reports a fatal item failure (bad URL, network error).
    static func run(url: String) {
        // Own session/process group so the menu bar app's killpg cleanly stops us.
        _ = setsid()

        guard let streamURL = URL(string: url),
              let scheme = streamURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            FileHandle.standardError.write(Data("focus: refusing to stream non-http(s) URL\n".utf8))
            exit(1)
        }

        let item = AVPlayerItem(url: streamURL)
        let player = AVPlayer(playerItem: item)
        // Live radio: prefer instant start over buffer-to-avoid-stalls.
        player.automaticallyWaitsToMinimizeStalling = false

        // Exit the subprocess on stream failure so a stale PID file doesn't keep
        // us in a fake "playing" state forever.
        let center = NotificationCenter.default
        let failed = AVPlayerItem.failedToPlayToEndTimeNotification
        let stalled = AVPlayerItem.playbackStalledNotification
        _ = center.addObserver(forName: failed, object: item, queue: .main) { note in
            let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "unknown"
            FileHandle.standardError.write(Data("focus: stream failed: \(err)\n".utf8))
            exit(1)
        }
        _ = center.addObserver(forName: stalled, object: item, queue: .main) { _ in
            // Stalls happen — don't exit, just note. A retry strategy could go here.
            FileHandle.standardError.write(Data("focus: stream stalled\n".utf8))
        }

        player.play()
        // Block on the run loop; SIGTERM terminates the process and AVPlayer with it.
        RunLoop.current.run()
    }
}
