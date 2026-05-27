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
        private let stdoutDrain: PipeDrain?

        fileprivate init(process: Process, stdoutPipe: Pipe?) {
            self.process = process
            self.stdoutDrain = stdoutPipe.map(PipeDrain.init)
        }

        var pid: Int32 { process.processIdentifier }

        /// Install a termination callback. Called once when the process exits;
        /// `stdout` is the captured output (empty if `captureStdout` was false).
        /// Calling `onExit` more than once replaces the previous handler.
        func onExit(_ handler: @Sendable @escaping (_ status: Int32, _ stdout: String) -> Void) {
            let drain = stdoutDrain
            process.terminationHandler = { proc in
                let out = drain?.collect() ?? ""
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

        // Start draining both pipes BEFORE waitUntilExit so a writer that
        // overruns the kernel pipe buffer doesn't block while we wait.
        let outDrain = outPipe.map(PipeDrain.init)
        let errDrain = errPipe.map(PipeDrain.init)
        p.waitUntilExit()

        return Result(
            status: p.terminationStatus,
            stdout: outDrain?.collect() ?? "",
            stderr: errDrain?.collect() ?? ""
        )
    }

    /// Launch a command without waiting. Use the returned `Handle` to read the
    /// PID, observe termination, or read captured stdout (delivered to `onExit`
    /// once the process exits). Capture begins immediately so a chatty child
    /// can't deadlock on a full pipe buffer before the handler fires.
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

/// Drains a `Pipe` to EOF on a background serial queue. The async-then-sync
/// pattern means the writer can fill the pipe past the kernel buffer without
/// blocking, and `collect()` waits for EOF before returning — establishing a
/// happens-before for the captured Data.
private final class PipeDrain: @unchecked Sendable {
    private let queue = DispatchQueue(label: "focus.shell.pipe-drain")
    private var data = Data()

    init(_ pipe: Pipe) {
        queue.async { [weak self] in
            self?.data = pipe.fileHandleForReading.readDataToEndOfFile()
        }
    }

    func collect() -> String {
        let bytes = queue.sync { data }
        return String(data: bytes, encoding: .utf8) ?? ""
    }
}
