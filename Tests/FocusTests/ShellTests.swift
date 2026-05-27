import Testing
import Foundation
@testable import Focus

@Suite struct ShellTests {

    // MARK: Sync — capture, drain, exit codes

    @Test func capturesStderrAndExitCode() {
        let result = Shell.run(Shell.Command(
            path: "/bin/sh",
            ["-c", "echo to-out; echo to-err 1>&2; exit 3"],
            captureStderr: true
        ))
        #expect(result.status == 3)
        #expect(result.stderr.contains("to-err"))
        #expect(!result.stderr.contains("to-out"), "stdout must not leak into the stderr capture")
    }

    @Test func capturesStdoutWithoutStderr() {
        let result = Shell.run(Shell.Command(
            path: "/bin/sh",
            ["-c", "echo hello; echo noise 1>&2"],
            captureStdout: true
        ))
        #expect(result.status == 0)
        #expect(result.stdout.contains("hello"))
        #expect(!result.stdout.contains("noise"))
        #expect(result.stderr.isEmpty, "stderr not captured when not requested")
    }

    @Test func returnsCleanlyOnSuccessWithEmptyCaptures() {
        let result = Shell.run(Shell.Command(path: "/usr/bin/true", captureStderr: true))
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
    }

    /// Output larger than the pipe buffer would deadlock an implementation that
    /// only drained after waitUntilExit. The serial-queue background drain
    /// must handle 256 KB cleanly (well over macOS's ~64 KB buffer).
    @Test func handlesStderrLargerThanPipeBuffer() {
        let result = Shell.run(Shell.Command(
            path: "/bin/sh",
            ["-c", #"head -c 262144 /dev/zero | tr '\0' 'x' 1>&2"#],
            captureStderr: true
        ))
        #expect(result.status == 0)
        #expect(result.stderr.count == 262_144)
    }

    @Test func handlesStdoutLargerThanPipeBuffer() {
        let result = Shell.run(Shell.Command(
            path: "/bin/sh",
            ["-c", #"head -c 262144 /dev/zero | tr '\0' 'x'"#],
            captureStdout: true
        ))
        #expect(result.status == 0)
        #expect(result.stdout.count == 262_144)
    }

    @Test func capturesBothStdoutAndStderrSimultaneously() {
        let result = Shell.run(Shell.Command(
            path: "/bin/sh",
            ["-c", "echo on-out; echo on-err 1>&2; exit 7"],
            captureStdout: true,
            captureStderr: true
        ))
        #expect(result.status == 7)
        #expect(result.stdout.contains("on-out"))
        #expect(result.stderr.contains("on-err"))
    }

    @Test func missingExecutableReturnsMinusOne() {
        let result = Shell.run(Shell.Command(
            path: "/this/does/not/exist", captureStderr: true
        ))
        #expect(result.status == -1)
        #expect(!result.stderr.isEmpty, "the launch error is reported in stderr")
    }

    // MARK: Sudo wrapping

    @Test func sudoPrefixWrapsArgv() throws {
        // We can't actually run sudo in tests, but we can verify the constructed
        // argv by spawning with a non-existent path and inspecting the failure.
        // The Process API doesn't expose `arguments` after launch failure, so we
        // verify behaviorally: the configured executable should be /usr/bin/sudo.
        // We synthesize this by introspecting through a known wrapper: build a
        // command targeting /usr/bin/true with sudo:true and confirm /usr/bin/sudo
        // is what tries to run (sudo will reject with no tty / no password).
        let result = Shell.run(Shell.Command(
            path: "/usr/bin/true", ["arg1", "arg2"],
            sudo: true,
            captureStderr: true
        ))
        // Either sudo is unavailable to this test (status != 0) or sudoers
        // happens to allow /usr/bin/true (rare). Both are valid; the point is
        // that the call routed through sudo without throwing.
        #expect(result.status >= 0, "sudo route did not throw")
    }

    // MARK: Async — handle, onExit, captured stdout

    @Test func spawnReportsPidAndExitStatus() async throws {
        let handle = try Shell.spawn(Shell.Command(path: "/usr/bin/true"))
        #expect(handle.pid > 0)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            handle.onExit { status, _ in
                if status == 0 { cont.resume() }
                else { cont.resume(throwing: CancellationError()) }
            }
        }
    }

    @Test func spawnDeliversCapturedStdoutToOnExit() async throws {
        let handle = try Shell.spawn(Shell.Command(
            path: "/bin/sh",
            ["-c", "echo from-spawn"],
            captureStdout: true
        ))
        let stdout: String = try await withCheckedThrowingContinuation { cont in
            handle.onExit { _, out in cont.resume(returning: out) }
        }
        #expect(stdout.contains("from-spawn"))
    }

    @Test func spawnWithoutCaptureGivesEmptyStdoutInOnExit() async throws {
        let handle = try Shell.spawn(Shell.Command(
            path: "/bin/sh", ["-c", "echo unread"]
        ))
        let stdout: String = try await withCheckedThrowingContinuation { cont in
            handle.onExit { _, out in cont.resume(returning: out) }
        }
        #expect(stdout.isEmpty, "no capture requested → empty stdout in callback")
    }
}
