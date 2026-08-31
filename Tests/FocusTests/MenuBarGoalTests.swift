import Testing
@testable import Focus

/// The menu bar label's text. Pure string work, so no scratch preferences
/// domain and no serialization needed.
struct MenuBarGoalTests {

    @Test func labelIsTheCountdownAloneWhenTheGoalIsOff() {
        #expect(menuBarLabel(countdown: 754, goal: "Write the spec", showGoal: false) == "12:34")
    }

    @Test func labelAppendsTheGoalWhenOn() {
        #expect(menuBarLabel(countdown: 754, goal: "Write the spec", showGoal: true)
                == "12:34  Write the spec")
    }

    /// `focus pomodoro start "  "` is accepted by the CLI, and a bare separator
    /// would widen the status item for nothing.
    @Test func labelLeavesOutAGoalThatIsAllWhitespace() {
        #expect(menuBarLabel(countdown: 754, goal: "   ", showGoal: true) == "12:34")
    }

    @Test func labelCapsTheGoalItAppends() {
        #expect(menuBarLabel(countdown: 5, goal: String(repeating: "x", count: 40), showGoal: true)
                == "0:05  " + String(repeating: "x", count: 19) + "\u{2026}")
    }

    @Test func shortGoalPassesThrough() {
        #expect(menuBarGoal("Write the spec") == "Write the spec")
    }

    @Test func goalAtTheLimitIsNotTruncated() {
        let exactly20 = "abcdefghijklmnopqrst"
        #expect(exactly20.count == 20)
        #expect(menuBarGoal(exactly20) == exactly20)
    }

    @Test func longGoalIsCappedAtTheLimit() {
        let capped = menuBarGoal("Refactor the payment reconciliation module")
        #expect(capped.count == 20)
        #expect(capped.hasSuffix("…"))
        #expect(capped == "Refactor the paymen…")
    }

    /// A goal pasted from a note can carry newlines; the status item is one line.
    @Test func whitespaceCollapsesToSingleSpaces() {
        #expect(menuBarGoal("  Write\n  the   spec  ") == "Write the spec")
    }

    /// The ellipsis follows the last word rather than a stranded space.
    @Test func trailingSpaceIsDroppedBeforeTheEllipsis() {
        #expect(menuBarGoal("abcdefghijklmnopqr st") == "abcdefghijklmnopqr…")
    }

    /// Counting Characters, not UTF-16: an emoji goal shouldn't be cut mid-glyph.
    @Test func multiByteCharactersCountAsOne() {
        let capped = menuBarGoal(String(repeating: "🍅", count: 30))
        #expect(capped == String(repeating: "🍅", count: 19) + "…")
    }
}
