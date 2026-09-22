import TalosAdapters
import TalosOrchestration
@testable import TalosUI
import Testing

/// The persistent input the Session Console owes — "one input line for talking
/// to the agent." A submitted message is shown in the transcript at once so the
/// conversation reads whole, and a follow-up turn resumes the same session and
/// appends to the existing transcript rather than replacing it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Suite("Session console follow-up input")
@MainActor
struct SessionConsoleViewModelFollowUpTests {
    /// A user message is shown as its own transcript row, distinct from agent
    /// output — the whole conversation, not only the agent's half.
    @Test("A submitted message is appended to the transcript as the user's own turn")
    func appendsUserMessageAsItsOwnRow() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()

        viewModel.appendUserMessage("Rename it to \"Dark\".")

        #expect(viewModel.lines.last?.content == .userMessage("Rename it to \"Dark\"."))
    }

    /// Appending a user message mid-stream closes the open output line, so the
    /// agent's next output opens a fresh line after the user's turn rather than
    /// folding into the line that was streaming.
    @Test("A user message mid-stream closes the open output line")
    func userMessageClosesTheOpenOutputLine() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Working on it"))

        viewModel.appendUserMessage("Also rename the file.")
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "On it now"))

        let payloads = viewModel.lines.map(\.outputPayload)
        #expect(payloads.contains("Working on it"), "the streaming line is finalized, not overwritten")
        #expect(payloads.contains("On it now"), "later output opens a new line after the user's turn")
    }

    @Test("A follow-up turn re-arms the running state without clearing the transcript")
    func followUpTurnAppendsRatherThanResets() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "What should the new title be?\n"))
        viewModel.handle(.terminated(AgentTermination(reason: .exited(code: 0), resumeToken: "s-1")))

        viewModel.beginFollowUpTurn()
        #expect(viewModel.isRunning, "clearing the termination re-arms the running state")

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Renaming to \"Dark\".\n"))
        let after = viewModel.lines.map(\.outputPayload)
        #expect(after.contains("What should the new title be?"), "the prior transcript is kept, not cleared")
        #expect(after.contains("Renaming to \"Dark\"."), "the follow-up output appends to it")
    }

    @Test("Beginning a follow-up turn before any session has started is a no-op")
    func noOpBeforeStart() {
        let viewModel = SessionConsoleViewModel()
        viewModel.beginFollowUpTurn()
        #expect(viewModel.state == .empty)
        #expect(!viewModel.isRunning)
    }

    @Test("Starting a fresh session clears the prior conversation, including user turns")
    func freshSessionClearsUserTurns() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()
        viewModel.appendUserMessage("First session message.")

        viewModel.sessionStarted()

        #expect(viewModel.lines.isEmpty, "a new session does not inherit the prior one's user turns")
    }
}
