import Testing
import Foundation
@testable import Focus

@Suite struct ReconnectPolicyTests {

    // MARK: The default schedule: 5 attempts, 1s doubling backoff

    @Test func firstRetryWaitsTheBaseDelay() {
        #expect(ReconnectPolicy().retryDelay(failureNumber: 1) == 1)
    }

    @Test func eachLaterRetryDoublesTheWait() {
        let policy = ReconnectPolicy()
        #expect(policy.retryDelay(failureNumber: 2) == 2)
        #expect(policy.retryDelay(failureNumber: 3) == 4)
        #expect(policy.retryDelay(failureNumber: 4) == 8)
    }

    @Test func budgetExhaustionSaysGiveUp() {
        let policy = ReconnectPolicy()
        // 5 total attempts means failures 1..4 retry and failure 5 does not.
        #expect(policy.retryDelay(failureNumber: 4) != nil)
        #expect(policy.retryDelay(failureNumber: 5) == nil)
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
