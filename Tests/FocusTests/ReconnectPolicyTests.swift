import Testing
import Foundation
@testable import Focus

@Suite struct ReconnectPolicyTests {

    // MARK: The default schedule: 12 attempts, 1s doubling backoff capped at 30s

    @Test func firstRetryWaitsTheBaseDelay() {
        #expect(ReconnectPolicy().retryDelay(failureNumber: 1) == 1)
    }

    @Test func eachLaterRetryDoublesTheWait() {
        let policy = ReconnectPolicy()
        #expect(policy.retryDelay(failureNumber: 2) == 2)
        #expect(policy.retryDelay(failureNumber: 3) == 4)
        #expect(policy.retryDelay(failureNumber: 4) == 8)
        #expect(policy.retryDelay(failureNumber: 5) == 16)
    }

    @Test func backoffStopsGrowingAtTheCap() {
        let policy = ReconnectPolicy()
        #expect(policy.retryDelay(failureNumber: 6) == 30)
        #expect(policy.retryDelay(failureNumber: 11) == 30)
    }

    @Test func budgetRidesOutAMultiMinuteOutage() {
        let policy = ReconnectPolicy()
        let total = (1..<policy.maxAttempts).compactMap(policy.retryDelay).reduce(0, +)
        #expect(total >= 180, "a connection drop of a few minutes must not end the music")
    }

    @Test func budgetExhaustionSaysGiveUp() {
        let policy = ReconnectPolicy()
        // 12 total attempts means failures 1..11 retry and failure 12 does not.
        #expect(policy.retryDelay(failureNumber: 11) != nil)
        #expect(policy.retryDelay(failureNumber: 12) == nil)
    }

    // MARK: The knobs move the schedule

    @Test func customBaseDelayScales() {
        let policy = ReconnectPolicy(maxAttempts: 3, baseDelay: 3)
        #expect(policy.retryDelay(failureNumber: 1) == 3)
        #expect(policy.retryDelay(failureNumber: 2) == 6)
        #expect(policy.retryDelay(failureNumber: 3) == nil, "maxAttempts 3 allows two retries")
    }

    @Test func singleAttemptNeverRetries() {
        #expect(ReconnectPolicy(maxAttempts: 1, baseDelay: 1).retryDelay(failureNumber: 1) == nil)
    }
}
