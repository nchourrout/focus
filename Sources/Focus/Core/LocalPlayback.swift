import Foundation
import Darwin

/// Focus audio playback, whatever the source. Streams run in a detached
/// `_stream-play` subprocess driven by AVPlayer; local files go to `afplay`,
/// looped by a `_afplay-loop` subprocess when asked. Both are tracked through
/// the same PID file, so `stop()` reaches either one.
///
/// No shell is involved on the hot path, so filenames with metacharacters are safe.
enum LocalPlayback {
    /// Stop whatever is playing and start this station. `loop` only applies to
    /// local files; streams run until stopped either way.
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
        // playing without re-deriving it from the stream URL.
        try "\(handle.pid)\n\(station.label)".write(to: Paths.musicPid, atomically: true, encoding: .utf8)
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
    }

    /// The menu bar asks for this once a second, so it costs one file read and
    /// one liveness probe rather than repeating both per property.
    static var playing: Playing {
        guard let lines = trackedLines(), let pid = lines.first.flatMap(Int32.init),
              isPIDAlive(pid) else {
            return Playing(isPlaying: false, station: nil)
        }
        return Playing(isPlaying: true, station: lines.count > 1 ? Station(label: lines[1]) : nil)
    }

    static var isPlaying: Bool { playing.isPlaying }

    static func stop() {
        guard let pid = trackedLines()?.first.flatMap(Int32.init), pid > 0 else {
            try? FileManager.default.removeItem(at: Paths.musicPid)
            return
        }
        // Don't signal an already-dead PID — the OS may have recycled it to an
        // unrelated process (group), and `killpg` would hit that instead.
        if isPIDAlive(pid) {
            // Signal the whole process group. The loop/stream wrapper makes itself
            // a session leader, so killpg also reaches its child (afplay or AVPlayer).
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
        // Default SIGTERM terminates the process; afplay child receives it too via the group.
        while true {
            let result = Shell.run(Shell.Command(path: "/usr/bin/afplay", [file], captureStderr: true))
            guard result.status != 0 else { continue }
            // Missing file, bad format, or SIGTERM. Detached process, so the log
            // is the only place this can be seen.
            Log.playback.notice(
                "afplay loop ended (status \(result.status, privacy: .public)): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)"
            )
            return
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
