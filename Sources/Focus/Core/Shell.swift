import Foundation

/// Single entry point for spawning external processes.
///
/// Every caller builds a `Command` and chooses between `run` (sync, returns
/// `Result`) and `spawn` (async, returns a `Handle` you can observe). The
/// config absorbs what used to be four separate wrappers plus several bespoke
/// `Process()` builds: silencing stdio, capturing pipes without deadlocking on
/// large output, wrapping with `/usr/bin/sudo -n` for the sudoers drop-in, and
/// firing a callback on termination.
enum Shell {

    /// Describes one external invocation. Stdio not marked for capture is
    /// silenced (`/dev/null`); set `captureStdout` / `captureStderr` to read it
    /// off the handle or the result.
    struct Command {
        var executable: URL
        var arguments: [String]
        var environment: [String: String]?
        /// Wrap with `/usr/bin/sudo -n` so the call uses the sudoers drop-in.
        /// Equivalent to setting `executable = /usr/bin/sudo` and prepending
        /// `["-n", original-executable.path]` to `arguments`.
        var sudo: Bool
        var captureStdout: Bool
        var captureStderr: Bool

        init(
            _ executable: URL,
            _ arguments: [String] = [],
            environment: [String: String]? = nil,
            sudo: Bool = false,
            captureStdout: Bool = false,
            captureStderr: Bool = false
        ) {
            self.executable = executable
            self.arguments = arguments
            self.environment = environment
            self.sudo = sudo
            self.captureStdout = captureStdout
            self.captureStderr = captureStderr
        }

        /// Convenience for callers that have a path string rather than a URL.
        init(
            path: String,
            _ arguments: [String] = [],
            environment: [String: String]? = nil,
            sudo: Bool = false,
            captureStdout: Bool = false,
            captureStderr: Bool = false
        ) {
            self.init(
                URL(fileURLWithPath: path), arguments,
                environment: environment, sudo: sudo,
                captureStdout: captureStdout, captureStderr: captureStderr
            )
        }
    }

    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    /// Async-process observer. Owns the underlying `Process` so callers can
    /// query the PID, watch for termination, or read captured stdout once
    /// `onExit` has fired.
    final class Handle {
        let process: Process
        private let stdoutPipe: Pipe?

        fileprivate init(process: Process, stdoutPipe: Pipe?) {
            self.process = process
            self.stdoutPipe = stdoutPipe
        }

        var pid: Int32 { process.processIdentifier }

        /// Install a termination callback. Called once when the process exits;
        /// `stdout` is the captured bytes (empty if `captureStdout` was false).
        func onExit(_ handler: @Sendable @escaping (_ status: Int32, _ stdout: String) -> Void) {
            let pipe = stdoutPipe
            process.terminationHandler = { proc in
                let out = pipe.flatMap {
                    String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                } ?? ""
                handler(proc.terminationStatus, out)
            }
        }
    }

    /// Run a command synchronously. Captured pipes are drained on a background
    /// queue so a noisy child can't deadlock on a full pipe buffer (~64 KB on
    /// macOS) while we sit in `waitUntilExit`.
    @discardableResult
    static func run(_ command: Command) -> Result {
        let p = configured(command)

        let outPipe: Pipe? = command.captureStdout ? Pipe() : nil
        let errPipe: Pipe? = command.captureStderr ? Pipe() : nil
        if let outPipe { p.standardOutput = outPipe }
        if let errPipe { p.standardError = errPipe }

        do {
            try p.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: "\(error)")
        }

        // Drain each captured pipe on its own queue before waitUntilExit. The
        // serial-queue ordering plus the sync read after wait establishes a
        // happens-before for the captured Data and avoids a race.
        var outData = Data()
        var errData = Data()
        let outQueue = outPipe.map { _ in DispatchQueue(label: "focus.shell.stdout-drain") }
        let errQueue = errPipe.map { _ in DispatchQueue(label: "focus.shell.stderr-drain") }
        if let outPipe, let outQueue {
            outQueue.async { outData = outPipe.fileHandleForReading.readDataToEndOfFile() }
        }
        if let errPipe, let errQueue {
            errQueue.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        }

        p.waitUntilExit()

        let outBytes = outQueue.map { $0.sync { outData } } ?? Data()
        let errBytes = errQueue.map { $0.sync { errData } } ?? Data()
        return Result(
            status: p.terminationStatus,
            stdout: String(data: outBytes, encoding: .utf8) ?? "",
            stderr: String(data: errBytes, encoding: .utf8) ?? ""
        )
    }

    /// Launch a command without waiting. Use the returned `Handle` to read the
    /// PID, observe termination, or read captured stdout (only valid inside the
    /// `onExit` callback).
    @discardableResult
    static func spawn(_ command: Command) throws -> Handle {
        let p = configured(command)
        let outPipe: Pipe? = command.captureStdout ? Pipe() : nil
        if let outPipe { p.standardOutput = outPipe }
        try p.run()
        return Handle(process: p, stdoutPipe: outPipe)
    }

    // MARK: Private

    /// Build a Process with the command's executable / arguments / sudo prefix
    /// applied and stdio defaulted to /dev/null. Caller overrides stdout/stderr
    /// before calling `run` / `spawn` when capture is requested.
    private static func configured(_ command: Command) -> Process {
        let p = Process()
        if command.sudo {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            p.arguments = ["-n", command.executable.path] + command.arguments
        } else {
            p.executableURL = command.executable
            p.arguments = command.arguments
        }
        if let env = command.environment {
            p.environment = env
        }
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        return p
    }
}
