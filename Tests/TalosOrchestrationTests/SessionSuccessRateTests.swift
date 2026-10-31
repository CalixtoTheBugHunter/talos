import Foundation
import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Asserts the success-rate computation AC4 requires: the rate is
/// `Succeeded ÷ (Succeeded + Failed)`, `Denied` and `Stopped` are excluded and
/// counted rather than silently dropped, and an empty or all-excluded set has
/// no rate at all rather than a fabricated 0% or 100%.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
@Suite("Session success rate")
struct SessionSuccessRateTests {
    private func record(
        _ outcome: SessionOutcomeClassification,
        subFunction: SubFunction = .assistant
    ) -> StoredSessionRecord {
        StoredSessionRecord(
            id: UUID(),
            project: ProjectIdentifier(rawValue: "p1"),
            subFunction: subFunction,
            agentName: "test-agent",
            outcome: outcome,
            startedAt: Date(timeIntervalSince1970: 0),
            duration: 1,
            toolCallCount: 0,
            approvalCount: 0,
            denialCount: 0,
            retryCount: 0,
            tokenOverheadRatio: 0
        )
    }

    @Test("The rate is Succeeded over Succeeded plus Failed")
    func rateIsSucceededOverSucceededPlusFailed() {
        let rate = SessionSuccessRate(records: [
            record(.succeeded), record(.succeeded), record(.succeeded), record(.failed)
        ])

        #expect(rate.fraction == 0.75)
        #expect(rate.ratedCount == 4)
    }

    @Test("Denied and Stopped are excluded from the rate and counted as coverage")
    func deniedAndStoppedAreExcludedAndCounted() {
        let rate = SessionSuccessRate(records: [
            record(.succeeded), record(.failed),
            record(.denied), record(.stopped), record(.stopped)
        ])

        // One of two rated sessions succeeded — the three excluded ones move
        // neither the numerator nor the denominator.
        #expect(rate.fraction == 0.5)
        #expect(rate.ratedCount == 2)
        #expect(rate.excludedCount == 3)
        #expect(rate.denied == 1)
        #expect(rate.stopped == 2)
    }

    @Test("An empty set has no rate, not a zero")
    func emptySetHasNoRate() {
        let rate = SessionSuccessRate(records: [StoredSessionRecord]())

        #expect(rate.fraction == nil)
        #expect(rate.ratedCount == 0)
    }

    @Test("A set of only excluded outcomes has no rate, not a zero")
    func allExcludedHasNoRate() {
        let rate = SessionSuccessRate(records: [
            record(.denied), record(.stopped)
        ])

        #expect(rate.fraction == nil)
        #expect(rate.excludedCount == 2)
    }

    @Test("The summary breaks the rate out per sub-function")
    func summaryBreaksOutPerSubFunction() {
        let summary = SessionMetricsSummary(records: [
            record(.succeeded, subFunction: .assistant),
            record(.failed, subFunction: .assistant),
            record(.succeeded, subFunction: .automator),
            record(.denied, subFunction: .automator)
        ])

        #expect(summary.overall.fraction == 2.0 / 3.0)
        #expect(summary.bySubFunction[.assistant]?.fraction == 0.5)
        // Automator's one denial is excluded, so its only rated session
        // succeeded — a 100% rate over a coverage of one.
        #expect(summary.bySubFunction[.automator]?.fraction == 1.0)
        #expect(summary.bySubFunction[.automator]?.excludedCount == 1)
    }

    @Test("A sub-function with no sessions in range is absent, not zeroed")
    func absentSubFunctionIsNotZeroed() {
        let summary = SessionMetricsSummary(records: [record(.succeeded, subFunction: .assistant)])

        #expect(summary.bySubFunction[.advisor] == nil)
        #expect(summary.bySubFunction[.selfImprover] == nil)
    }
}
