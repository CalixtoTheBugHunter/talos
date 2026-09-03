import SwiftUI
import TalosAdapters
import TalosUI
import Testing

/// Verifies ``SessionConsoleViewModel`` against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
/// — output that appends incrementally, dispatches through the pluggable
/// renderer interface, and announces one meaningful unit at a time.
@Suite("Session console view model")
struct SessionConsoleViewModelTests {
    @Test("A chunk with no newline grows one open line without disturbing earlier ones")
    @MainActor
    func chunkWithNoNewlineGrowsOneOpenLine() {
        let viewModel = SessionConsoleViewModel()

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Reading the "))
        let firstLineID = viewModel.lines.last?.id
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "file tree."))

        #expect(viewModel.lines.count == 1)
        #expect(viewModel.lines.last?.id == firstLineID)
        #expect(viewModel.lines.last?.element.payload == "Reading the file tree.")
    }

    @Test("A newline finalizes exactly the text before it and opens a new line for the remainder")
    @MainActor
    func newlineFinalizesTheLineBeforeIt() {
        let viewModel = SessionConsoleViewModel()

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Found 3 matches.\nStill "))
        let finalizedID = viewModel.lines.first?.id
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "searching."))

        #expect(viewModel.lines.count == 2)
        #expect(viewModel.lines[0].id == finalizedID)
        #expect(viewModel.lines[0].element.payload == "Found 3 matches.")
        #expect(viewModel.lines[1].element.payload == "Still searching.")
    }

    @Test("A finalized line never changes once a later chunk arrives")
    @MainActor
    func finalizedLineNeverChangesAgain() {
        let viewModel = SessionConsoleViewModel()
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "First line.\n"))
        let finalizedLine = viewModel.lines[0]

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Second line.\n"))
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Third line.\n"))

        #expect(viewModel.lines[0] == finalizedLine)
    }

    @Test("A 100k+ character single chunk round-trips into the expected finalized lines")
    @MainActor
    func veryLargeChunkRoundTrips() {
        let viewModel = SessionConsoleViewModel()
        let longRun = String(repeating: "a", count: 120_000)

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Before.\n\(longRun)\nAfter."))

        #expect(viewModel.lines.count == 3)
        #expect(viewModel.lines[0].element.payload == "Before.")
        #expect(viewModel.lines[1].element.payload == longRun)
        #expect(viewModel.lines[2].element.payload == "After.")
    }

    @Test("Every line is markdown-kind data, dispatched through the registry rather than a hardcoded renderer")
    @MainActor
    func linesDispatchThroughTheRegistry() {
        let spy = SpyRenderer()
        var registry = OutputRendererRegistry()
        registry.register(.markdown, renderer: spy)
        let viewModel = SessionConsoleViewModel(renderers: registry)
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Some output.\n"))

        #expect(viewModel.lines[0].element.kind == .markdown)
        _ = viewModel.renderers.view(for: viewModel.lines[0].element)
        #expect(spy.received == viewModel.lines[0].element)
    }

    @Test("handle(_:) ignores tool calls and permission requests, but not output or termination")
    @MainActor
    func handleIgnoresToolCallsAndPermissionRequestsButNotTermination() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()

        viewModel.handle(.toolCall(AgentToolCall(id: "call-1", name: "Read")))
        viewModel.handle(.output(AgentOutputChunk(channel: .standardOutput, text: "Reading.")))
        viewModel.handle(.permissionRequest(AgentPermissionRequest(id: "req-1", prompt: "Delete a file?")))

        #expect(viewModel.lines.count == 1)
        #expect(viewModel.lines[0].element.payload == "Reading.")
        #expect(viewModel.state == .ready)

        let termination = AgentTermination(reason: .exited(code: 1))
        viewModel.handle(.terminated(termination))
        #expect(viewModel.state == .failed(termination))
    }

    @Test("state starts empty and moves to loading once the session begins")
    @MainActor
    func stateStartsEmptyThenLoading() {
        let viewModel = SessionConsoleViewModel()
        #expect(viewModel.state == .empty)

        viewModel.sessionStarted()
        #expect(viewModel.state == .loading)
    }

    @Test("state is ready once output has arrived")
    @MainActor
    func stateIsReadyOnceOutputArrives() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Reading.\n"))

        #expect(viewModel.state == .ready)
    }

    @Test("a non-zero exit moves state to failed, carrying the agent's own termination")
    @MainActor
    func nonZeroExitMovesStateToFailed() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Reading.\n"))

        let termination = AgentTermination(reason: .exited(code: 1), lastOutput: "Reading.\n")
        viewModel.handle(.terminated(termination))

        #expect(viewModel.state == .failed(termination))
    }

    @Test("failing to launch moves state to failed even with no output at all")
    @MainActor
    func failedToLaunchMovesStateToFailedWithNoOutput() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()

        let termination = AgentTermination(reason: .failedToLaunch)
        viewModel.handle(.terminated(termination))

        #expect(viewModel.state == .failed(termination))
    }

    @Test("a denied termination moves state to denied")
    @MainActor
    func deniedTerminationMovesStateToDenied() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()

        let termination = AgentTermination(reason: .denied)
        viewModel.handle(.terminated(termination))

        #expect(viewModel.state == .denied(termination))
    }

    @Test("a clean exit leaves state ready rather than failed")
    @MainActor
    func cleanExitLeavesStateReady() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Done.\n"))

        viewModel.handle(.terminated(AgentTermination(reason: .exited(code: 0))))

        #expect(viewModel.state == .ready)
    }

    @Test("a stop leaves state ready rather than failed or denied")
    @MainActor
    func stopLeavesStateReady() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Done.\n"))

        viewModel.handle(.terminated(AgentTermination(reason: .stopped)))

        #expect(viewModel.state == .ready)
    }

    @Test("Following output starts true, and pause/resume are event-driven state toggles")
    @MainActor
    func followingOutputTogglesOnRequest() {
        let viewModel = SessionConsoleViewModel()
        #expect(viewModel.isFollowingOutput == true)

        viewModel.pauseFollowingOutput()
        #expect(viewModel.isFollowingOutput == false)

        viewModel.resumeFollowingOutput()
        #expect(viewModel.isFollowingOutput == true)
    }

    @Test("The announcer is called once per finalized line, never while a line is still open")
    @MainActor
    func announcerIsCalledOncePerFinalizedLine() {
        let announcer = SpyAnnouncer()
        let viewModel = SessionConsoleViewModel(announcer: announcer)

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Still "))
        #expect(announcer.announced.isEmpty)

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "streaming this token by "))
        #expect(announcer.announced.isEmpty)

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "token.\nNext line.\n"))
        #expect(announcer.announced == ["Still streaming this token by token.", "Next line."])
    }

    @Test("A blank line finalizing is not announced")
    @MainActor
    func blankLineIsNotAnnounced() {
        let announcer = SpyAnnouncer()
        let viewModel = SessionConsoleViewModel(announcer: announcer)

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "\n\nReal line.\n"))

        #expect(announcer.announced == ["Real line."])
    }
}

private final class SpyRenderer: OutputRenderer, @unchecked Sendable {
    private(set) var received: OutputElement?

    func view(for element: OutputElement) -> AnyView {
        received = element
        return AnyView(EmptyView())
    }
}

private final class SpyAnnouncer: SessionConsoleAnnouncing, @unchecked Sendable {
    private(set) var announced: [String] = []

    func announce(_ text: String) {
        announced.append(text)
    }
}
