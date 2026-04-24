import Foundation
import Darwin

/// Local audio file playback via `afplay`. Loop mode spawns a second instance of
/// this binary (`_afplay-loop`) that replays the file until killed. No shell is
/// involved on the hot path, so filenames with metacharacters are safe.
enum LocalPlayback {
    static func start(path: URL, loop: Bool) throws {
        stop()
        let (exe, args): (URL, [String]) = loop
            ? (Paths.selfExecutable, ["_afplay-loop", "--file", path.path])
            : (URL(fileURLWithPath: "/usr/bin/afplay"), [path.path])
        let p = try Subprocess.launchSilent(exe, args)
        try String(p.processIdentifier).write(to: Paths.musicPid, atomically: true, encoding: .utf8)
    }

    static func stop() {
        guard FileManager.default.fileExists(atPath: Paths.musicPid.path),
              let text = try? String(contentsOf: Paths.musicPid, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            try? FileManager.default.removeItem(at: Paths.musicPid)
            return
        }
        // Signal the whole process group. The loop wrapper makes itself a session
        // leader (see `runAfplayLoop`), so this also kills the current afplay child.
        _ = killpg(pid, SIGTERM)
        // Also hit the direct pid in case setsid didn't run yet.
        _ = kill(pid, SIGTERM)
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
