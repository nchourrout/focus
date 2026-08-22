import Foundation
import AVFoundation
import Darwin

/// HTTP audio stream player driven by AVPlayer. Mirrors `LocalPlayback.runAfplayLoop`
/// but for network streams instead of local files. Runs in a detached subprocess
/// (`_stream-play`) so the menu bar app and CLI use the same kill-by-PID stop path
/// as afplay.
///
/// Diagnostics go to `Log.playback`, not stderr: this process is always spawned
/// with its stdio on /dev/null, so stderr has no reader.
enum StreamPlayer {
    /// Body of the hidden `_stream-play` subcommand. Streams until SIGTERM, or
    /// until reconnects are exhausted (see `ReconnectPolicy`) — exiting then so
    /// a stale PID file doesn't keep us in a fake "playing" state forever.
    static func run(url: String) {
        // Own session/process group so the menu bar app's killpg cleanly stops us.
        _ = setsid()

        // This is a trust boundary — argv reaches us straight from a shell — so
        // validate, but through the same door everything else uses rather than
        // hand-rolling a second scheme check.
        guard let streamURL = Station(uri: url)?.streamURL else {
            Log.playback.error("refusing to stream non-http(s) URL: \(url, privacy: .public)")
            exit(1)
        }

        let policy = ReconnectPolicy()
        var failures = 0
        while true {
            let connectedAt = Date().timeIntervalSince1970
            playOnce(url: streamURL)

            // A connection that held for a while earns a fresh failure budget:
            // one dropout after hours of playback must not look like the tail
            // of a rapid-fire failure series.
            let now = Date().timeIntervalSince1970
            if now - connectedAt > 60 { failures = 0 }
            failures += 1

            guard let delay = policy.retryDelay(failureNumber: failures) else {
                Log.playback.error(
                    "stream failed \(failures, privacy: .public) times in quick succession; giving up"
                )
                exit(1)
            }
            Log.playback.error(
                "stream failed; reconnecting in \(delay, privacy: .public)s, attempt \(failures + 1, privacy: .public)/\(policy.maxAttempts, privacy: .public)"
            )
            Thread.sleep(forTimeInterval: delay)
        }
    }

    /// Connect and play until the item reports a fatal failure (which stops the
    /// current run loop) or the process is SIGTERMed. Blocks the caller.
    private static func playOnce(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // Live radio: prefer instant start over buffer-to-avoid-stalls.
        player.automaticallyWaitsToMinimizeStalling = false

        let center = NotificationCenter.default
        let failed = AVPlayerItem.failedToPlayToEndTimeNotification
        let stalled = AVPlayerItem.playbackStalledNotification
        let runLoop = RunLoop.current
        _ = center.addObserver(forName: failed, object: item, queue: .main) { note in
            let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "unknown"
            Log.playback.error("stream failed, leaving this connection: \(err, privacy: .public)")
            CFRunLoopStop(runLoop.getCFRunLoop())
        }
        _ = center.addObserver(forName: stalled, object: item, queue: .main) { _ in
            // Stalls happen — AVPlayer usually recovers on its own. Only a
            // terminal failure moves to the next connection.
            Log.playback.notice("stream stalled")
        }

        Log.playback.notice("streaming \(url.absoluteString, privacy: .public)")
        player.play()
        // Block on the run loop; SIGTERM terminates the process and AVPlayer with it.
        runLoop.run()
        player.pause()
    }
}

/// How many times a failing stream reconnects, and how long it waits between
/// tries. Pure so the schedule is testable without AVFoundation.
///
/// Defaults give five total attempts spaced 1s/2s/4s/8s apart — enough to ride
/// out a router blip or SomaFM restarting a mountpoint, without hanging onto a
/// dead URL all session. Callers pair it with a fresh-budget rule: a connection
/// that held for more than a minute resets the failure count, so isolated
/// dropouts never accumulate toward giving up.
struct ReconnectPolicy {
    /// Total attempts allowed, counting the first.
    var maxAttempts: Int = 5
    /// Wait before the second attempt; each later attempt doubles it.
    var baseDelay: TimeInterval = 1

    /// Backoff before the next try, given how many times the stream has failed
    /// so far (1-based). Nil means the budget is spent: give up.
    func retryDelay(failureNumber: Int) -> TimeInterval? {
        guard failureNumber <= maxAttempts - 1 else { return nil }
        return baseDelay * pow(2, Double(failureNumber - 1))
    }
}
