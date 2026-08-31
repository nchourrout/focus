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
    /// The outgoing stream is asked to stop, not killed: it ramps down over
    /// `AudioFade.stop` while this call returns, so switching stations ends the
    /// old one gently rather than clipping it. The two do not cross-fade, since
    /// the replacement still has to exec, connect and buffer before it makes any
    /// sound. The outgoing process is out of the PID file by then; it ends
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
        // File format: "pid\nlabel\nstarted_at". The label lets the menu bar say
        // what's playing without re-deriving it from the stream URL, and tells
        // `duckable` whether the process it would signal is a stream. The start
        // time is what makes signalling it safe at all; see `duckable`. It is
        // absent from files written by older builds, and from the rare case
        // where the process is gone before we can read it, which costs those
        // processes ducking and nothing else.
        var contents = "\(handle.pid)\n\(station.label)"
        if let startedAt = pidStartTime(handle.pid) { contents += "\n\(startedAt)" }
        try contents.write(to: Paths.musicPid, atomically: true, encoding: .utf8)
    }

    /// Start `station` unless it is already the thing playing.
    ///
    /// Restarting a stream costs a fade-out, a reconnect and a fade-in: a hole
    /// in the audio at exactly the moment it should be seamless. That is what
    /// the pomodoro daemon needs at a handoff, where `skip-break` gives one run
    /// to a replacement daemon playing the same station and nothing is wrong
    /// with the stream already running.
    ///
    /// Only automatic callers should use this. A user asking for a station is
    /// also the only way to recover one that is alive but silent, so
    /// `Actions.playMusic` restarts unconditionally.
    static func playIfNeeded(_ station: Station) throws {
        let current = playing
        guard !current.isPlaying || current.station != station else { return }
        try play(station)
    }

    /// A playback process that can be sent a duck request, identified strongly
    /// enough that sending one is safe. Callers hold it across the cue so the
    /// restore reaches the process that was ducked.
    struct Duckable: Equatable {
        var pid: Int32
        var startedAt: TimeInterval
    }

    /// The stream that can be ducked right now, or nil.
    ///
    /// Three things have to hold, and the third is the important one.
    ///
    /// It has to be a stream: a non-nil `streamURL` is exactly "this PID is a
    /// `_stream-play`", and afplay, which has no volume of its own, treats
    /// SIGUSR1 as fatal. It has to be alive. And its start time has to match the
    /// one recorded when it was spawned, because a PID alone does not identify a
    /// process for long. A `_stream-play` can exit without clearing the file
    /// (SIGKILL, a crash, or its own exit when reconnects are exhausted), the OS
    /// recycles the PID, and the next phase cue would then fire SIGUSR1 at an
    /// unrelated process and terminate it. Duck requests are automatic and land
    /// twice per cue, so this is not a risk worth carrying. It is the same guard
    /// `PomodoroDaemon` puts on the daemon PID before signalling it.
    ///
    /// A PID file without a start time (an older build) is left alone, which
    /// also covers the `_stream-play` that predates ducking and would die on the
    /// signal's default disposition.
    static var duckable: Duckable? {
        let current = playing
        guard let pid = current.pid, let startedAt = current.startedAt,
              current.station?.streamURL != nil else { return nil }
        return Duckable(pid: pid, startedAt: startedAt)
    }

    /// Drop `target` under a phase cue and bring it back up `duration` later.
    ///
    /// The whole timeline lives here because the process does. Two signals have
    /// to arrive in order, so they share a serial queue; the restore has to
    /// reach the stream that was ducked rather than whatever is playing when the
    /// cue ends, so the handle is held across the gap; and overlapping cues have
    /// to settle on one answer, so a later request supersedes an earlier one's
    /// restore instead of the two fighting.
    ///
    /// Returns immediately, and every signal goes out on the private queue.
    static func duck(_ target: Duckable, for duration: TimeInterval) {
        duckQueue.async {
            duckGeneration += 1
            let generation = duckGeneration
            setDucked(true, on: target)
            duckQueue.asyncAfter(deadline: .now() + duration) {
                // A newer cue owns the duck now, and will lift it on its own
                // schedule. Lifting here would raise the music mid-cue.
                guard duckGeneration == generation else { return }
                setDucked(false, on: target)
            }
        }
    }

    /// Serial, so a duck can never be overtaken by the restore that follows it.
    /// On a concurrent queue those two are unordered, and losing that race
    /// leaves the music down with nothing scheduled to lift it.
    private static let duckQueue = DispatchQueue(label: "focus.playback.duck")
    /// Guarded by `duckQueue`. Identifies which cue currently owns the duck.
    private static var duckGeneration = 0

    /// Send one duck or restore. Re-checks identity rather than trusting the
    /// `Duckable` it was handed: the restore lands seconds after the duck, and
    /// the stream can be stopped and its PID recycled in between.
    private static func setDucked(_ ducked: Bool, on target: Duckable) {
        guard isOurProcess(pid: target.pid, expectedStart: target.startedAt) else { return }
        // Addressed to the process, never the group. `stop` can afford killpg
        // because SIGTERM is survivable by anything it reaches; a stray SIGUSR1
        // is fatal by default, so it goes to the one PID we have just confirmed.
        _ = kill(target.pid, ducked ? SIGUSR1 : SIGUSR2)
    }

    /// What's playing right now, from a single read of the PID file.
    ///
    /// `station` is nil for the label-less PID files older builds wrote, so
    /// callers fall back to a generic "playing" state. Reads the same file
    /// `stop()` uses, which is why this reflects playback started by the CLI, the
    /// pomodoro daemon, or the menu bar alike — not just this process.
    struct Playing {
        /// Derived: a pid is recorded here only once it has been confirmed alive.
        var isPlaying: Bool { pid != nil }
        var station: Station?
        /// The tracked process, when it is alive. The menu bar only reads the
        /// two above; the callers that go on to signal it (`stop`, `duckable`)
        /// take it from here rather than parsing the file a second time.
        var pid: Int32?
        /// Its start time as recorded when it was spawned, for callers that must
        /// prove the PID has not been recycled. Nil for PID files written before
        /// builds recorded it.
        var startedAt: TimeInterval?
    }

    /// The menu bar asks for this once a second, so it costs one file read and
    /// one liveness probe rather than repeating both per property.
    static var playing: Playing {
        guard let lines = trackedLines(), let pid = lines.first.flatMap(Int32.init),
              isPIDAlive(pid) else {
            return Playing(station: nil, pid: nil, startedAt: nil)
        }
        return Playing(station: lines.count > 1 ? Station(label: lines[1]) : nil,
                       pid: pid,
                       startedAt: lines.count > 2 ? TimeInterval(lines[2]) : nil)
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

    /// PID-file lines: [pid, label?, started_at?]. Nil if the file is absent.
    private static func trackedLines() -> [String]? {
        guard let text = try? String(contentsOf: Paths.musicPid, encoding: .utf8) else {
            return nil
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
