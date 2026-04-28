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
        try launch(exe, args)
    }

    /// Launch a detached `_stream-play` subprocess to play an HTTP audio stream.
    /// Tracked via the same PID file as afplay, so `stop()` works for both.
    static func startStream(url: String) throws {
        try launch(Paths.selfExecutable, ["_stream-play", "--url", url])
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

    /// Stop any current playback, then start the new one and record its PID so
    /// `stop()` can reach it later regardless of which mode it's in.
    private static func launch(_ executable: URL, _ arguments: [String]) throws {
        stop()
        let p = try Subprocess.launchSilent(executable, arguments)
        try String(p.processIdentifier).write(to: Paths.musicPid, atomically: true, encoding: .utf8)
    }

    static func stop() {
        guard FileManager.default.fileExists(atPath: Paths.musicPid.path),
              let text = try? String(contentsOf: Paths.musicPid, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else {
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
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            proc.arguments = [file]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                return
            }
            if proc.terminationStatus != 0 { return }
        }
    }
}
