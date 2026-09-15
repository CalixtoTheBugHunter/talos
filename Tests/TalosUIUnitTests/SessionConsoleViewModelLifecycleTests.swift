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

    // MARK: - A new session starts from an empty transcript

    // One console outlives every session it shows, so a transcript left behind
    // renders as the new run's own output. Loading is the state that says the
    // prompt is with the agent, and `state` reads it off an empty transcript —
    // so inherited lines also make it unreachable for every run but the first.
    // § The five states every surface owes —
    // https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback

    @Test("A new session starts in Loading rather than inheriting the last one's transcript")
    func startingASessionClearsTheTranscript() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Cloning the wiki.\n"))
        viewModel.sessionConcluded(.stopped(Self.usage))

        viewModel.sessionStarted()

        #expect(viewModel.lines.isEmpty, "the previous session's transcript is not this session's output")
        #expect(viewModel.state == .loading, "a started session with no output yet is waiting for the agent")
    }

    @Test("A line from the previous session is gone from the next one's transcript")
    func aPreviousSessionsLineIsNotShownInTheNext() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Cloning the wiki."))

        viewModel.sessionStarted()
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Reading the README."))

        #expect(viewModel.lines.map(\.outputPayload) == ["Reading the README."])
    }

    @Test("Concluding a session that never started is a no-op")
    func noOpBeforeStart() {
        let viewModel = SessionConsoleViewModel()

        viewModel.sessionConcluded(.failed(reason: "never started", tokenReport: Self.usage))

        #expect(viewModel.termination == nil)
        #expect(viewModel.state == .empty)
    }
}
