import Foundation

/// Silent subprocess runner. Redirects stdio to /dev/null and returns the exit code.
enum Subprocess {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String] = [], environment: [String: String]? = nil) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        if let env = environment {
            p.environment = env
        }
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }

    /// Convenience for firing a small AppleScript. Returns 0 on success.
    @discardableResult
    static func osascript(_ source: String) -> Int32 {
        run("/usr/bin/osascript", ["-e", source])
    }

    /// Start a subprocess with stdio silenced and return it without waiting.
    /// Caller owns the Process for PID tracking / later termination.
    static func launchSilent(_ executable: URL, _ arguments: [String]) throws -> Process {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        return p
    }

    /// Run a subprocess synchronously, return (exit code, captured stderr as UTF-8).
    /// Used when we need to inspect stderr to distinguish error classes (e.g. osascript
    /// "User canceled (-128)" vs a real failure).
    static func runCapturingStderr(_ executable: String, _ arguments: [String] = []) -> (status: Int32, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let err = Pipe()
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = err
        do {
            try p.run()
            // Drain the pipe in the background so a noisy child can't block on a full
            // pipe buffer (~64 KB on macOS) while we sit in waitUntilExit. The serial
            // queue orders the async write before the sync read; the sync block also
            // establishes a happens-before for the captured `Data`, avoiding a race.
            var collected = Data()
            let drainQueue = DispatchQueue(label: "focus.subprocess.stderr-drain")
            drainQueue.async {
                collected = err.fileHandleForReading.readDataToEndOfFile()
            }
            p.waitUntilExit()
            let stderr = drainQueue.sync { collected }
            return (p.terminationStatus, String(data: stderr, encoding: .utf8) ?? "")
        } catch {
            return (-1, "\(error)")
        }
    }
}
