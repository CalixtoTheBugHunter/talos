@testable import TalosUI
import Testing

/// Decision 100: a message the user submits always reaches the agent. While a
/// turn runs it interrupts and supersedes that turn rather than starting a
/// second concurrent one (AC1); whether the superseding turn resumes the same
/// session or starts fresh turns on whether a resume token exists (AC2, AC4).
/// Interrupting means stopping, which is the fail-closed path that denies a
/// pending approval (AC3) — the stop-to-denial half is asserted end to end in
/// `ApprovalPromptCenterCancellationTests`; here the decision's own
/// `interruptsRunningTurn` locks that a running turn is stopped at all, which
/// is the only branch `SessionComposer.submitFollowUp` routes to a stop.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Suite("Session follow-up decision")
struct SessionFollowUpDecisionTests {
    @Test("A message sent while a turn runs interrupts it, resuming the same session")
    func interruptsAndResumesWhenRunning() {
        #expect(
            SessionFollowUpDecision.decide(isTurnRunning: true, hasResumeToken: true) == .interruptThenResume
        )
    }

    @Test("A message sent while the first turn runs, before a resume token exists, interrupts and starts fresh")
    func interruptsAndStartsFreshWhenRunningWithNoToken() {
        #expect(
            SessionFollowUpDecision.decide(isTurnRunning: true, hasResumeToken: false) == .interruptThenFreshStart
        )
    }

    @Test("A message sent with no turn running resumes the session at once")
    func resumesNowWhenIdleAndResumable() {
        #expect(
            SessionFollowUpDecision.decide(isTurnRunning: false, hasResumeToken: true) == .resumeNow
        )
    }

    @Test("A message sent with no turn running and nothing resumable starts a fresh session")
    func startsFreshWhenIdleAndNotResumable() {
        #expect(
            SessionFollowUpDecision.decide(isTurnRunning: false, hasResumeToken: false) == .freshStartNow
        )
    }

    @Test("Exactly the two running cases stop the turn first — the branch that denies a pending approval (AC1, AC3)")
    func onlyRunningDecisionsInterrupt() {
        #expect(SessionFollowUpDecision.interruptThenResume.interruptsRunningTurn)
        #expect(SessionFollowUpDecision.interruptThenFreshStart.interruptsRunningTurn)
        #expect(!SessionFollowUpDecision.resumeNow.interruptsRunningTurn)
        #expect(!SessionFollowUpDecision.freshStartNow.interruptsRunningTurn)
    }

    @Test("Only the token-backed cases resume the same session; the tokenless cases start fresh (AC2, AC4)")
    func onlyTokenBackedDecisionsResume() {
        #expect(SessionFollowUpDecision.interruptThenResume.resumesSameSession)
        #expect(SessionFollowUpDecision.resumeNow.resumesSameSession)
        #expect(!SessionFollowUpDecision.interruptThenFreshStart.resumesSameSession)
        #expect(!SessionFollowUpDecision.freshStartNow.resumesSameSession)
    }
}
