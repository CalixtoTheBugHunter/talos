import TalosAdapters
@testable import TalosOrchestration
import Testing

/// [Decision 60](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions):
/// "Inferred from the session's end state and typed as `Succeeded`, `Failed`,
/// `Denied`, or `Stopped`." Every `SessionOutcome` case collapses onto
/// exactly one of those four — this is the mapping, asserted case by case
/// rather than assumed from the enum's shape.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
@Suite("Session outcome classification")
struct SessionOutcomeClassificationTests {
    private static let tokens = TokenReport.measured(TokenCounts(input: 1, output: 1), model: "test-model")

    @Test("A clean exit classifies as succeeded")
    func succeededClassifiesAsSucceeded() {
        #expect(SessionOutcome.succeeded(Self.tokens).classification == .succeeded)
    }

    @Test("A non-zero exit classifies as failed")
    func failedClassifiesAsFailed() {
        let outcome = SessionOutcome.failed(reason: "The agent exited with code 1.", tokenReport: Self.tokens)
        #expect(outcome.classification == .failed)
    }

    @Test("A user stop classifies as stopped")
    func stoppedClassifiesAsStopped() {
        #expect(SessionOutcome.stopped(Self.tokens).classification == .stopped)
    }

    @Test("The agent terminating for denial classifies as denied")
    func agentTerminatedDenialClassifiesAsDenied() {
        #expect(SessionOutcome.denied(Self.tokens).classification == .denied)
    }

    /// Decision 47: "nothing was gated, so recording a denial would name a
    /// decision nobody made" — the pinned-overflow case is `.failed`, never
    /// `.denied`.
    @Test("A pinned-context overflow classifies as failed, never denied")
    func contextAssemblyFailureClassifiesAsFailed() {
        let failure = ContextAssemblyFailure(ceiling: 10, pinnedCosts: [])
        #expect(SessionOutcome.contextAssemblyFailed(failure).classification == .failed)
    }

    /// The session ended because the gate denied before any agent launched —
    /// exactly decision 60's own definition of `Denied`.
    @Test("A pre-check denial classifies as denied")
    func preCheckDenialClassifiesAsDenied() {
        let outcome = SessionOutcome.safeguardsPreCheckDenied(reason: "Production deploys need a human.")
        #expect(outcome.classification == .denied)
    }
}
