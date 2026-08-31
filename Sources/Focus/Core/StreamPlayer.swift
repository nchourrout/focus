import Foundation
import AVFoundation
import Darwin

/// HTTP audio stream player driven by AVPlayer. Mirrors `LocalPlayback.runAfplayLoop`
/// but for network streams instead of local files. Runs in a detached subprocess
/// (`_stream-play`) so the menu bar app and CLI use the same kill-by-PID stop path
/// as afplay.
///
/// Owning the whole process is also what makes the volume ours to move: nothing
/// else plays through this AVPlayer, so it can fade in on connect, fade out on a
/// stop request, and drop under a phase cue without touching the system volume
/// that every other app on the Mac shares.
///
/// Diagnostics go to `Log.playback`, not stderr: this process is always spawned
/// with its stdio on /dev/null, so stderr has no reader.
enum StreamPlayer {
    /// Body of the hidden `_stream-play` subcommand. Streams until SIGTERM, or
    /// until reconnects are exhausted (see `ReconnectPolicy`) exiting then so
    /// a stale PID file doesn't keep us in a fake "playing" state forever.
    static func run(url: String) {
        // Own session/process group so the menu bar app's killpg cleanly stops us.
        _ = setsid()

        // This is a trust boundary, since argv reaches us straight from a shell,
        // so validate, but through the same door everything else uses rather
        // than hand-rolling a second scheme check.
        guard let streamURL = Station(uri: url)?.streamURL else {
            Log.playback.error("refusing to stream non-http(s) URL: \(url, privacy: .public)")
            exit(1)
        }

        installSignalHandling()

        let policy = ReconnectPolicy()
        var failures = 0
        while true {
            let connectedAt = Date().timeIntervalSince1970
            playOnce(url: streamURL)

            // The connection is over. If that is because we are stopping, there
            // is nothing left to fade and nothing to reconnect to.
            if stopRequest.isSet { exit(0) }

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

    /// Set once a stop request arrives, so the reconnect loop can tell "this
    /// connection failed" from "we are on our way out".
    ///
    /// Without it, a connection that dies during the fade-out sends `playOnce`
    /// home, its `defer` cancels the fade (discarding the `exit(0)` the fade
    /// would have run), and the loop reconnects and starts a fresh 2s fade-in
    /// on a stream the user has already asked to stop. Only the watchdog ended
    /// that, a quarter second later.
    private final class StopRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var requested = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return requested }
        func set() { lock.lock(); requested = true; lock.unlock() }
    }
    private static let stopRequest = StopRequest()

    /// Connect and play until the item reports a fatal failure or the process is
    /// SIGTERMed. Blocks the caller; returning means this connection is done and
    /// the caller may reconnect.
    ///
    /// Failure arrives two ways and both matter. `failedToPlayToEndTime` covers a
    /// connection that dies mid-playback; an item that never opens at all (host
    /// down, refused connection, 404, the common case when the network drops)
    /// only ever moves its `status` to `.failed`, and posts no notification. The
    /// first version of this watched the notification alone and so sat forever on
    /// an unreachable URL.
    private static func playOnce(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // Live radio: prefer instant start over buffer-to-avoid-stalls.
        player.automaticallyWaitsToMinimizeStalling = false
        // Open silent. A stream that arrives at full level is an attention
        // event, which is the one thing focus music must never be. Every
        // connection fades in, reconnects included: audio slamming back after a
        // dropout pulls just as hard as audio slamming on at the start.
        player.volume = 0

        let runLoop = RunLoop.current
        // Set on the main thread only (the observers below deliver there), and
        // read by the run loop between passes, so no synchronisation is needed.
        var ended = false
        func endConnection(_ reason: String) {
            guard !ended else { return }
            ended = true
            Log.playback.error("stream failed, leaving this connection: \(reason, privacy: .public)")
            CFRunLoopStop(runLoop.getCFRunLoop())
        }

        let center = NotificationCenter.default
        let observers = [
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                               object: item, queue: .main) { note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                endConnection(error?.localizedDescription ?? "unknown")
            },
            center.addObserver(forName: AVPlayerItem.playbackStalledNotification,
                               object: item, queue: .main) { _ in
                // Stalls happen, and AVPlayer usually recovers on its own. Only a
                // terminal failure moves to the next connection.
                Log.playback.notice("stream stalled")
            },
        ]
        let statusObserver = item.observe(\.status, options: [.initial, .new]) { item, _ in
            guard item.status == .failed else { return }
            let reason = item.error?.localizedDescription ?? "unknown"
            // KVO delivers on whichever thread set the property; hop to main so
            // `ended` stays single-threaded.
            DispatchQueue.main.async { endConnection(reason) }
        }
        defer {
            statusObserver.invalidate()
            observers.forEach(center.removeObserver)
            // Drop the fade before the player: a timer left running would keep
            // writing volume into a connection that is already over.
            cancelFade()
            currentPlayer = nil
        }

        Log.playback.notice("streaming \(url.absoluteString, privacy: .public)")
        currentPlayer = player
        player.play()
        fade(to: targetVolume, over: AudioFade.start)
        // Drive the run loop a pass at a time rather than calling `run()`, which
        // re-enters `runMode` after every stop and so can never be broken out of:
        // CFRunLoopStop would just start the next pass, leaving the reconnect in
        // `run(url:)` unreachable. `run(mode:before:)` returning false means no
        // input sources are left, which is also the end of this connection.
        while !ended, runLoop.run(mode: .default, before: .distantFuture) {}
        player.pause()
    }

    // MARK: Volume

    // The three below are main-thread-only state. Every mutation arrives either
    // from `playOnce` (already on main) or through a `DispatchQueue.main.async`
    // hop out of the signal queue, so none of it needs a lock.

    /// The player for the connection in progress, nil between connections.
    private static var currentPlayer: AVPlayer?
    /// The ramp in flight, if any. At most one: a new fade replaces it.
    private static var fadeTimer: Timer?
    /// Whether a phase cue is currently holding the music down.
    private static var ducked = false

    /// Where a fade should land when nothing interrupts it. Full is 1.0:
    /// AVPlayer's volume is relative to system output, so the fades are the only
    /// thing that ever moves it away from whatever the Mac is set to.
    private static var targetVolume: Float {
        ducked ? AudioFade.duckLevel : 1
    }

    /// Ramp the current player to `target`, replacing any fade in flight.
    ///
    /// Starts from the player's live volume rather than the previous fade's
    /// endpoint, so interrupting a ramp halfway (a stop request landing during
    /// the fade-in, a cue landing during the fade back up) continues from where
    /// the sound actually is instead of jumping.
    private static func fade(to target: Float, over duration: TimeInterval,
                             then completion: (() -> Void)? = nil) {
        cancelFade()
        guard let player = currentPlayer else {
            completion?()
            return
        }
        let curve = VolumeFade(from: player.volume, to: target, duration: duration)
        let startedAt = Date()
        // 60 Hz. Volume steps start to be heard as steps rather than as a slope
        // somewhere above 20 ms apart, and this costs nothing at these lengths.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startedAt)
            player.volume = curve.volume(atElapsed: elapsed)
            guard elapsed >= duration else { return }
            timer.invalidate()
            fadeTimer = nil
            completion?()
        }
        fadeTimer = timer
        // `.default` is the mode `playOnce` drives the run loop in.
        RunLoop.main.add(timer, forMode: .default)
    }

    private static func cancelFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    // MARK: Signals

    private static let signalQueue = DispatchQueue(label: "focus.stream.signal")
    /// Retained for the life of the process; see `SignalTraps`.
    private static var signalSources: [DispatchSourceSignal] = []

    /// Catch the four signals `LocalPlayback` sends.
    ///
    /// SIGTERM and SIGINT fade out before exiting, instead of cutting the
    /// waveform wherever it happened to be. SIGUSR1 and SIGUSR2 duck the music
    /// under a phase cue and bring it back; they are signals rather than a
    /// control file because a duck that arrives late is worse than no duck, and
    /// because the sender already holds our PID.
    private static func installSignalHandling() {
        signalSources = SignalTraps.install(on: signalQueue, [
            (SIGTERM, { fadeOutAndExit() }),
            (SIGINT, { fadeOutAndExit() }),
            (SIGUSR1, { setDucked(true) }),
            (SIGUSR2, { setDucked(false) }),
        ])
    }

    /// Runs on the signal queue. Asks the run loop for the ramp, and arms a
    /// deadline rather than waiting to be told the fade finished: the run loop
    /// may be parked in the reconnect backoff, which is a plain `Thread.sleep`,
    /// and a stop request must not hang on that. Whichever fires first ends the
    /// process. Scheduled rather than slept so the queue stays free for the
    /// other three sources.
    private static func fadeOutAndExit() {
        stopRequest.set()
        DispatchQueue.main.async {
            fade(to: 0, over: AudioFade.stop) { exit(0) }
        }
        signalQueue.asyncAfter(deadline: .now() + AudioFade.stop + 0.25) { exit(0) }
    }

    /// Runs on the signal queue. `ducked` is read back by the next connection's
    /// fade-in, so a cue that lands while the stream is reconnecting still has
    /// the music come back underneath it rather than over it.
    private static func setDucked(_ wantsDuck: Bool) {
        DispatchQueue.main.async {
            ducked = wantsDuck
            fade(to: targetVolume, over: wantsDuck ? AudioFade.duckDown : AudioFade.duckUp)
        }
    }
}

/// How many times a failing stream reconnects, and how long it waits between
/// tries. Pure so the schedule is testable without AVFoundation.
///
/// Defaults give five total attempts spaced 1s/2s/4s/8s apart, enough to ride
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
