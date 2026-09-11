import TalosAdapters
import TalosOrchestration
@testable import TalosUI
import Testing

/// Verifies ``SessionConsoleViewModel/sessionConcluded(_:)`` — the mapping the
/// composer relies on to move the console out of Loading for the pipeline's
/// pre-stream terminal paths (a launch failure, a pre-check denial), which emit
/// no `.terminated` to the stream. Each ``SessionOutcome`` maps to the
/// ``AgentTerminationReason`` the five-states view then reads, and a concluded
/// outcome never overwrites a termination the stream already reported.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
@Suite("Session console lifecycle")
@MainActor
struct SessionConsoleViewModelLifecycleTests {
    private static let usage = TokenReport.measured(TokenCounts(input: 1, output: 1), model: "test-model")

    /// `.contextAssemblyFailed` shares the `.failed` arm (both → `.failedToLaunch`)
    /// and needs a TalosOrchestration-internal initializer to construct, so
    /// `.failed` stands in for that arm; every distinct reason is covered.
    @Test("Each pre-stream outcome maps to the termination reason the view reads")
    func outcomeMapsToTerminationReason() {
        let cases: [(SessionOutcome, AgentTerminationReason)] = [
            (.succeeded(Self.usage), .exited(code: 0)),
            (.stopped(Self.usage), .stopped),
            (.denied(Self.usage), .denied),
            (.safeguardsPreCheckDenied(reason: "the gate refused before launch"), .denied),
            (.failed(reason: "the agent crashed", tokenReport: Self.usage), .failedToLaunch)
        ]
        for (outcome, expected) in cases {
            let viewModel = SessionConsoleViewModel()
            viewModel.sessionStarted()
            viewModel.sessionConcluded(outcome)
            #expect(viewModel.termination?.reason == expected, "\(outcome) should map to \(expected)")
        }
    }

    @Test("A concluded outcome never overwrites a termination the stream already reported")
    func doesNotOverwriteAStreamedTermination() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()
        let streamed = AgentTermination(reason: .exited(code: 2), lastOutput: "boom")
        viewModel.handle(.terminated(streamed))

        viewModel.sessionConcluded(.succeeded(Self.usage))

        #expect(viewModel.termination == streamed, "a streamed termination must win over the concluded outcome")
    }

    @Test("Concluding a session that never started is a no-op")
    func noOpBeforeStart() {
        let viewModel = SessionConsoleViewModel()

        viewModel.sessionConcluded(.failed(reason: "never started", tokenReport: Self.usage))

        #expect(viewModel.termination == nil)
        #expect(viewModel.state == .empty)
    }
}
