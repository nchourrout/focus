import Testing
import Foundation
@testable import Focus

@Suite struct SubprocessTests {
    @Test func capturesStderrAndExitCode() {
        let result = Subprocess.runCapturingStderr(
            "/bin/sh",
            ["-c", "echo to-out; echo to-err 1>&2; exit 3"]
        )
        #expect(result.status == 3)
        #expect(result.stderr.contains("to-err"))
        #expect(!result.stderr.contains("to-out"), "stdout must not leak into the stderr capture")
    }

    @Test func returnsCleanlyOnSuccessWithEmptyStderr() {
        let result = Subprocess.runCapturingStderr("/usr/bin/true")
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
    }

    /// Stderr larger than the pipe buffer would deadlock an implementation that
    /// only drained after waitUntilExit. The serial-queue background drain
    /// must handle 256 KB cleanly (well over macOS's ~64 KB buffer).
    @Test func handlesStderrLargerThanPipeBuffer() {
        let result = Subprocess.runCapturingStderr(
            "/bin/sh",
            ["-c", #"head -c 262144 /dev/zero | tr '\0' 'x' 1>&2"#]
        )
        #expect(result.status == 0)
        #expect(result.stderr.count == 262_144)
    }
}
