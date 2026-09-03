import TalosAdapters
import TalosCore
import TalosSafeguards
import TalosUI
import Testing

/// Verifies the part of ``SessionConsoleViewModel`` this issue adds: tool
/// calls rendered inline as they happen, and a pending approval presented
/// inline — "where the work is happening" — rather than as a detached
/// modal.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Suite("Session console tool calls and inline approval")
struct SessionConsoleToolCallApprovalTests {
    @Test("A tool call renders inline as its own row, with the name and targets the agent stated")
    @MainActor
    func toolCallRendersAsItsOwnRow() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()

        viewModel.handle(.toolCall(AgentToolCall(id: "call-1", name: "Read", targets: ["Sources/Foo.swift"])))

        #expect(viewModel.lines.count == 1)
        guard case let .toolCall(call) = viewModel.lines[0].content else {
            Issue.record("expected a tool call line")
            return
        }
        #expect(call.callID == "call-1")
        #expect(call.name == "Read")
        #expect(call.targets == ["Sources/Foo.swift"])
        #expect(call.approval == .notGated)
    }

    @Test("handle(_:) ignores permission requests — present(_:action:tier:) is the real channel")
    @MainActor
    func handleIgnoresPermissionRequestsButNotOutputToolCallsOrTermination() {
        let viewModel = SessionConsoleViewModel()
        viewModel.sessionStarted()

        viewModel.handle(.toolCall(AgentToolCall(id: "call-1", name: "Read")))
        viewModel.handle(.output(AgentOutputChunk(channel: .standardOutput, text: "Reading.")))
        viewModel.handle(.permissionRequest(AgentPermissionRequest(id: "req-1", prompt: "Delete a file?")))

        #expect(viewModel.lines.count == 2)
        #expect(viewModel.lines[1].outputPayload == "Reading.")
        #expect(viewModel.state == .ready)

        let termination = AgentTermination(reason: .exited(code: 1))
        viewModel.handle(.terminated(termination))
        #expect(viewModel.state == .failed(termination))
    }

    @Test("A tool call interrupts and closes whatever text line was still open")
    @MainActor
    func toolCallClosesTheOpenTextLine() {
        let announcer = SpyAnnouncer()
        let viewModel = SessionConsoleViewModel(announcer: announcer)

        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "Still typing"))
        viewModel.handle(.toolCall(AgentToolCall(id: "call-1", name: "Read")))
        viewModel.appendOutput(AgentOutputChunk(channel: .standardOutput, text: "New line."))

        #expect(viewModel.lines.count == 3)
        #expect(viewModel.lines[0].outputPayload == "Still typing")
        #expect(announcer.announced == ["Still typing"])
        guard case .toolCall = viewModel.lines[1].content else {
            Issue.record("expected the tool call between the two output lines")
            return
        }
        #expect(viewModel.lines[2].outputPayload == "New line.")
    }

    @Test("present(_:action:tier:) upgrades the correlated call to pending, announces it, resolving clears the slot")
    @MainActor
    func presentUpgradesTheCorrelatedCallAndResolves() async {
        let announcer = SpyAnnouncer()
        let viewModel = SessionConsoleViewModel(announcer: announcer)
        viewModel.handle(.toolCall(AgentToolCall(id: "call-1", name: "Write", targets: ["Sources/Foo.swift"])))
        let request = AgentPermissionRequest(id: "call-1", prompt: "Write to Sources/Foo.swift?")

        let task = Task { await viewModel.present(request, action: .fileWrite, tier: .write) }
        while !viewModel.hasPendingApprovalForTesting {
            await Task.yield()
        }

        guard case let .toolCall(pending) = viewModel.lines[0].content else {
            Issue.record("expected the tool call line")
            return
        }
        #expect(pending.approval == .pending(request: request, action: .fileWrite, tier: .write))
        #expect(announcer.announced == ["Approval needed. Write to Sources/Foo.swift?"])

        viewModel.resolvePendingApproval(with: .allowed)

        #expect(await task.value == .allowed)
        guard case let .toolCall(resolved) = viewModel.lines[0].content else {
            Issue.record("expected the tool call line")
            return
        }
        #expect(resolved.approval == .resolved(action: .fileWrite, tier: .write, outcome: .allowed))
        #expect(!viewModel.hasPendingApprovalForTesting)
    }

    @Test("present(_:action:tier:) synthesizes a row when no tool call ever preceded the request")
    @MainActor
    func presentSynthesizesARowWhenNoToolCallPreceded() async {
        let viewModel = SessionConsoleViewModel()
        let request = AgentPermissionRequest(id: "req-1", prompt: "Delete a file?", toolName: "Bash")

        let task = Task { await viewModel.present(request, action: .fileDelete, tier: .irreversible) }
        while !viewModel.hasPendingApprovalForTesting {
            await Task.yield()
        }

        #expect(viewModel.lines.count == 1)
        guard case let .toolCall(call) = viewModel.lines[0].content else {
            Issue.record("expected a synthesized tool call line")
            return
        }
        #expect(call.callID == "req-1")
        #expect(call.name == "Bash")

        viewModel.resolvePendingApproval(with: .denied)
        #expect(await task.value == .denied)
    }

    @Test("Cancelling the awaiting task resolves nil and marks the row denied, attributed to Talos")
    @MainActor
    func cancellationResolvesNilAndMarksDenied() async {
        let viewModel = SessionConsoleViewModel()
        viewModel.handle(.toolCall(AgentToolCall(id: "call-1", name: "Delete")))
        let request = AgentPermissionRequest(id: "call-1", prompt: "Delete a file?")

        let task = Task { await viewModel.present(request, action: .fileDelete, tier: .irreversible) }
        while !viewModel.hasPendingApprovalForTesting {
            await Task.yield()
        }

        task.cancel()

        #expect(await task.value == nil)
        guard case let .toolCall(call) = viewModel.lines[0].content else {
            Issue.record("expected the tool call line")
            return
        }
        #expect(call.approval == .resolved(action: .fileDelete, tier: .irreversible, outcome: .denied))
    }

    /// Cancelling before `present(_:action:tier:)` ever suspends is a real
    /// race — Stop cancels the session task independently of where the gate
    /// happens to be. A row that cannot be resolved must never be shown as
    /// pending, so this asserts the row stays at `.notGated` rather than a
    /// `.pending` no control can ever answer — the same guarantee
    /// ``ApprovalPromptCenter`` gives by showing nothing in the equivalent
    /// race.
    @Test("Cancelling before the continuation exists never leaves the row stuck pending")
    @MainActor
    func cancellingBeforeTheContinuationExistsNeverLeavesTheRowStuckPending() async {
        let viewModel = SessionConsoleViewModel()
        viewModel.handle(.toolCall(AgentToolCall(id: "call-1", name: "Delete")))
        let request = AgentPermissionRequest(id: "call-1", prompt: "Delete a file?")

        let task = Task { await viewModel.present(request, action: .fileDelete, tier: .irreversible) }
        task.cancel() // cancel immediately, before `present` has had a chance to suspend

        #expect(await task.value == nil)
        guard case let .toolCall(call) = viewModel.lines[0].content else {
            Issue.record("expected the tool call line")
            return
        }
        #expect(call.approval == .notGated, "never shown as pending, so never stuck pending")
        #expect(!viewModel.hasPendingApprovalForTesting)
    }
}

/// A pending approval is never observable through public API alone — it is
/// consumed the moment ``SessionConsoleViewModel/resolvePendingApproval(with:)``
/// answers it — so tests poll this rather than the continuation itself,
/// mirroring the same `while center.current == nil { await Task.yield() }`
/// pattern ``ApprovalPromptCenterTests`` already uses for the same shape of
/// suspend-then-resolve API.
private extension SessionConsoleViewModel {
    var hasPendingApprovalForTesting: Bool {
        lines.contains { line in
            guard case let .toolCall(call) = line.content else { return false }
            guard case .pending = call.approval else { return false }
            return true
        }
    }
}
