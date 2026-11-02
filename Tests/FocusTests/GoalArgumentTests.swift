import Testing
import Foundation
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

@Suite struct TodoGoalTests {
    @Test func startNeedsAGoalOrATodo() {
        #expect(throws: (any Error).self) { _ = try Pomodoro.Start.parse([]) }
        #expect(throws: (any Error).self) { _ = try Pomodoro.Start.parse(["spec", "--todo", "1"]) }
    }

    @Test func todoNamesTheGoal() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("todo-goal-\(UUID().uuidString)")
        let list = TodoList(url: dir.appendingPathComponent("todos.json"),
                            lockPath: dir.appendingPathComponent(".lock").path)
        try list.add("write spec")
        let start = try Pomodoro.Start.parse(["--todo", "1"])
        #expect(try start.resolvedGoal(list: list) == "write spec")
        #expect(throws: (any Error).self) {
            _ = try Pomodoro.Start.parse(["--todo", "2"]).resolvedGoal(list: list)
        }
        try list.setDone(.number(1), true)
        #expect(throws: (any Error).self, "a done task is not a goal") {
            _ = try start.resolvedGoal(list: list)
        }
    }
}
