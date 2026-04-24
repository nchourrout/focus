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
}
