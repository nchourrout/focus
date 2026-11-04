import Testing
@testable import Focus

@Suite struct IncrementControlTests {

    @Test func aStepLandsOnTheNextMultiple() {
        #expect(IncrementControl.stepped(25, by: 5, in: 1...180) == 30)
        #expect(IncrementControl.stepped(25, by: -5, in: 1...180) == 20)
    }

    /// A value set from the CLI snaps back onto the grid rather than keeping
    /// its offset forever.
    @Test func anOffGridValueSnapsOntoTheGrid() {
        #expect(IncrementControl.stepped(23, by: 5, in: 1...180) == 25)
        #expect(IncrementControl.stepped(23, by: -5, in: 1...180) == 20)
    }

    @Test func theRangeClampsBothEnds() {
        #expect(IncrementControl.stepped(5, by: -5, in: 1...180) == 1, "the floor is the range, not zero")
        #expect(IncrementControl.stepped(1, by: -5, in: 1...180) == 1)
        #expect(IncrementControl.stepped(1, by: 5, in: 1...180) == 5)
        #expect(IncrementControl.stepped(180, by: 5, in: 1...180) == 180)
    }

    @Test func aUnitStepIsPlainCounting() {
        #expect(IncrementControl.stepped(4, by: 1, in: 1...12) == 5)
        #expect(IncrementControl.stepped(4, by: -1, in: 1...12) == 3)
    }

    /// Set out of range with `defaults write`: "More" must not lower it.
    @Test func aValuePastTheEndStaysPut() {
        #expect(IncrementControl.stepped(240, by: 5, in: 1...180) == 240)
        #expect(IncrementControl.stepped(240, by: -5, in: 1...180) == 180)
    }
}
