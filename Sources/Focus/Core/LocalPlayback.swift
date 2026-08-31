import Foundation
import Darwin

/// Focus audio playback, whatever the source. Streams run in a detached
/// `_stream-play` subprocess driven by AVPlayer; local files go to `afplay`,
/// looped by a `_afplay-loop` subprocess when asked. Both are tracked through
/// the same PID file, so `stop()` reaches either one.
///
/// The PID file is also the control channel. Everything that touches playback
/// (the menu bar, the CLI, the pomodoro daemon) is a different process from the
/// one making the sound, so starting, stopping, and ducking all go through the
/// PID it records rather than through an in-process player handle.
///
/// No shell is involved on the hot path, so filenames with metacharacters are safe.
enum LocalPlayback {
    /// Stop whatever is playing and start this station. `loop` only applies to
    /// local files; streams run until stopped either way.
    ///
    /// The stop and the start overlap on purpose. A stream asked to stop fades
    /// out over `AudioFade.stop` while the replacement fades in over
    /// `AudioFade.start`, so switching stations crossfades instead of leaving a
    /// hole. The outgoing process is no longer in the PID file by then; it ends
    /// itself when its fade does, and its own watchdog covers the case where it
    /// somehow cannot.
    static func play(_ station: Station, loop: Bool = false) throws {
        let (executable, arguments): (URL, [String])
        switch station {
        case .preset, .stream:
            executable = Paths.selfExecutable
            arguments = ["_stream-play", "--url", station.uri]
        case .file(let url):
            if loop {
                executable = Paths.selfExecutable
                arguments = ["_afplay-loop", "--file", url.path]
            } else {
                executable = URL(fileURLWithPath: "/usr/bin/afplay")
                arguments = [url.path]
            }
        }
        stop()
        let handle = try Shell.spawn(Shell.Command(executable, arguments))
        // File format: "pid\nlabel". The label lets the menu bar say what's
        // playing without re-deriving it from the stream URL, and tells
        // `setDucked` whether the process it would signal is a stream.
        try "\(handle.pid)\n\(station.label)".write(to: Paths.musicPid, atomically: true, encoding: .utf8)
    }

    /// Start `station` unless it is already the thing playing.
    ///
    /// Restarting a stream costs a fade-out, a reconnect and a fade-in: a hole
    /// in the audio at exactly the moments it should be seamless. Two callers
    /// need that not to happen. The pomodoro daemon starts music at every
    /// handoff, and `skip-break` hands one run to a replacement daemon that
    /// plays the same station. The music menu marks the playing station with a
    /// checkmark, and clicking the one already checked should do nothing rather
    /// than interrupt it.
    ///
    static func playIfNeeded(_ station: Station) throws {
        let current = playing
        guard !current.isPlaying || current.station != station else { return }
        try play(station)
    }

    /// Drop the music under a phase cue, or bring it back up.
    ///
    /// Only a stream is asked: a non-nil `streamURL` is exactly "this PID is a
    /// `_stream-play`". Local files go through afplay, which has no volume of
    /// its own and treats SIGUSR1 as fatal, and a label-less PID file from an
    /// older build reads as no station at all, which is the same conservatism.
    ///
    /// One case is knowingly left uncovered: a `_stream-play` spawned by a build
    /// that predates ducking dies on SIGUSR1's default disposition. That needs
    /// the binary to be replaced while music plays, costs one silenced stream
    /// and one click, and heals itself. Encoding a capability in the PID file to
    /// prevent it would leave a line in an on-disk format forever.
    static func setDucked(_ ducked: Bool) {
        let current = playing
        guard let pid = current.pid, current.station?.streamURL != nil else { return }
        // Addressed to the process, never the group. `stop` can afford killpg
        // because SIGTERM is survivable by anything it reaches; a stray SIGUSR1
        // is fatal by default, so it goes to the one PID we know handles it.
        _ = kill(pid, ducked ? SIGUSR1 : SIGUSR2)
    }

    /// What's playing right now, from a single read of the PID file.
    ///
    /// `station` is nil for the label-less PID files older builds wrote, so
    /// callers fall back to a generic "playing" state. Reads the same file
    /// `stop()` uses, which is why this reflects playback started by the CLI, the
    /// pomodoro daemon, or the menu bar alike — not just this process.
    struct Playing {
        var isPlaying: Bool
        var station: Station?
        /// The tracked process, when it is alive. The menu bar only reads the
        /// two above; the callers that go on to signal it (`stop`, `setDucked`)
        /// take it from here rather than parsing the file a second time.
        var pid: Int32?
    }

    /// The menu bar asks for this once a second, so it costs one file read and
    /// one liveness probe rather than repeating both per property.
    static var playing: Playing {
        guard let lines = trackedLines(), let pid = lines.first.flatMap(Int32.init),
              isPIDAlive(pid) else {
            return Playing(isPlaying: false, station: nil, pid: nil)
        }
        return Playing(isPlaying: true,
                       station: lines.count > 1 ? Station(label: lines[1]) : nil,
                       pid: pid)
    }

    static var isPlaying: Bool { playing.isPlaying }

    /// Ask playback to stop. Returns as soon as the signal is away: a stream
    /// takes `AudioFade.stop` to ramp down before it exits, so the sound
    /// outlives this call by about a second. The PID file goes now regardless,
    /// which is what the caller and the menu bar both want to see.
    static func stop() {
        // A nil pid is a missing file, an unparseable one, or a PID that is
        // already dead. Signalling a dead PID is what we must not do: the OS may
        // have recycled it to an unrelated process (group), and `killpg` would
        // hit that instead.
        if let pid = playing.pid {
            // Signal the whole process group. The loop/stream wrapper makes itself
            // a session leader, so killpg also reaches its child (afplay or AVPlayer).
            // `_stream-play` catches this and fades out before exiting; afplay
            // dies on the default disposition, as it always has.
            _ = killpg(pid, SIGTERM)
            _ = kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(at: Paths.musicPid)
    }

    /// Body of the hidden `_afplay-loop` subcommand. Loops afplay forever, exiting on
    /// SIGTERM or if afplay itself errors (missing file, bad format).
    static func runAfplayLoop(file: String) {
        // Become our own session/process group so the outer `killpg` cleanly takes out
        // both this wrapper and its current afplay child.
        _ = Darwin.setsid()
        // A degenerate file (truncated, zero-length) can make afplay exit 0
        // immediately; looping on that would tight-spin the CPU. Five instant
        // "successes" in a row mean the file never actually plays — give up,
        // leaving the stale PID file to age out honestly in the menu bar.
        let quickExitWindow = 0.5
        let maxQuickExits = 5
        var quickExits = 0
        // Default SIGTERM terminates the process; afplay child receives it too via the group.
        while true {
            let startedAt = Date().timeIntervalSince1970
            let result = Shell.run(Shell.Command(path: "/usr/bin/afplay", [file], captureStderr: true))
            let elapsed = Date().timeIntervalSince1970 - startedAt
            if result.status != 0 {
                // Missing file, bad format, or SIGTERM. Detached process, so the log
                // is the only place this can be seen.
                Log.playback.notice(
                    "afplay loop ended (status \(result.status, privacy: .public)): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)"
                )
                return
            }
            if elapsed > quickExitWindow {
                quickExits = 0
                continue
            }
            quickExits += 1
            guard quickExits < maxQuickExits else {
                Log.playback.error(
                    "afplay exited instantly \(maxQuickExits, privacy: .public)x for \(file, privacy: .public); not looping further"
                )
                return
            }
        }
    }

    // MARK: Private

    /// PID-file lines: [pid, label?]. Nil if the file is absent.
    private static func trackedLines() -> [String]? {
        guard let text = try? String(contentsOf: Paths.musicPid, encoding: .utf8) else {
            return nil
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
