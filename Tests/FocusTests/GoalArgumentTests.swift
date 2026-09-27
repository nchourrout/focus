import Testing
@testable import Focus

/// A goal is free text, and free text can start with "-".
@Suite struct GoalArgumentTests {
    private let daemonArgs = ["--work-end", "1", "--break-end", "2",
                              "--work-minutes", "25", "--break-minutes", "5"]

    @Test func theDaemonAcceptsAGoalStartingWithADash() throws {
        let run = try PomodoroRun.parse(["--goal=-10% latency"] + daemonArgs)
        #expect(run.goal == "-10% latency")
    }

    /// Pins why `spawn` passes `--goal=<goal>`: the two-token form is rejected.
    @Test func theTwoTokenFormRejectsIt() {
        #expect(throws: (any Error).self) {
            _ = try PomodoroRun.parse(["--goal", "-10% latency"] + daemonArgs)
        }
    }

    @Test func startAcceptsItAfterTheTerminator() throws {
        let start = try Pomodoro.Start.parse(["--", "--fix auth"])
        #expect(start.goal == "--fix auth")
    }
}
