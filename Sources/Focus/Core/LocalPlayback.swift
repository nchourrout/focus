import Foundation
import Darwin

/// Local audio file playback via `afplay`. Loop mode spawns a second instance of
/// this binary (`_afplay-loop`) that replays the file until killed. No shell is
/// involved on the hot path, so filenames with metacharacters are safe.
enum LocalPlayback {
    static func start(path: URL, loop: Bool) throws {
        let (exe, args): (URL, [String]) = loop
            ? (Paths.selfExecutable, ["_afplay-loop", "--file", path.path])
            : (URL(fileURLWithPath: "/usr/bin/afplay"), [path.path])
        try launch(exe, args, label: path.lastPathComponent)
    }

    /// Launch a detached `_stream-play` subprocess to play an HTTP audio stream.
    /// Tracked via the same PID file as afplay, so `stop()` works for both.
    static func startStream(url: String) throws {
        // Callers pass resolved URIs (the daemon round-trips through the CLI),
        // so map back to the preset name here — it's the label the menu shows.
        let label = MusicPresets.name(forURI: url) ?? url
        try launch(Paths.selfExecutable, ["_stream-play", "--url", url], label: label)
    }

    /// One-call helper: resolve a preset name / URI and start playback. Used by
    /// the menu bar app's music actions; the CLI's `MusicCommand.run` does the
    /// equivalent inline because it needs different output messaging per case.
    static func play(target: String) throws {
        guard let uri = try MusicPresets.resolve(target: target, explicitURI: nil) else {
            throw CLIError.missingMusicSource
        }
        guard uri.hasPrefix("http://") || uri.hasPrefix("https://") else {
            throw MusicPresets.ResolveError.unknownPreset(target)
        }
        try startStream(url: uri)
    }

    /// Stop any current playback, then start the new one and record its PID plus
    /// a display label (preset name, URL, or filename) so `stop()` can reach it
    /// later and the menu bar can say what's playing. File format: "pid\nlabel".
    private static func launch(_ executable: URL, _ arguments: [String], label: String) throws {
        stop()
        let handle = try Shell.spawn(Shell.Command(executable, arguments))
        try "\(handle.pid)\n\(label)".write(to: Paths.musicPid, atomically: true, encoding: .utf8)
    }

    /// Read and parse the tracked playback PID, or nil if the file is absent or
    /// malformed. Shared by `isPlaying` and `stop()`.
    private static func trackedPID() -> Int32? {
        guard let line = trackedLines()?.first else { return nil }
        return Int32(line)
    }

    /// PID-file lines: [pid, label?]. Nil if the file is absent.
    private static func trackedLines() -> [String]? {
        guard let text = try? String(contentsOf: Paths.musicPid, encoding: .utf8) else {
            return nil
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// True if a tracked playback process is currently alive. Reads the same PID
    /// file `stop()` uses, so it reflects playback started by the CLI, the
    /// pomodoro daemon, or the menu bar alike — not just this process.
    static var isPlaying: Bool {
        guard let pid = trackedPID() else { return false }
        return isPIDAlive(pid)
    }

    /// Display label of the current playback (preset name, URL, or filename),
    /// or nil when nothing is playing. Empty-label PID files (written by older
    /// builds) report nil too — callers fall back to a generic "playing" state.
    static var nowPlaying: String? {
        guard isPlaying, let lines = trackedLines(), lines.count > 1 else { return nil }
        let label = lines[1]
        return label.isEmpty ? nil : label
    }

    static func stop() {
        guard let pid = trackedPID(), pid > 0 else {
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
            let result = Shell.run(Shell.Command(path: "/usr/bin/afplay", [file]))
            if result.status != 0 { return }
        }
    }
}
