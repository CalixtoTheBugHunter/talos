import TalosAdapters
import TalosCore
import TalosSafeguards
import TalosUI
import Testing

private func makeRequest(id: String = "r1") -> AgentPermissionRequest {
    AgentPermissionRequest(id: id, prompt: "do the thing")
}

@Suite("Approval prompt center: present and resolve")
struct ApprovalPromptCenterResolveTests {
    @Test("Presenting a request publishes it as current, and resolving it returns the decision")
    @MainActor
    func presentPublishesAndResolveReturnsTheDecision() async {
        let center = ApprovalPromptCenter()
        let request = makeRequest()

        let task = Task { await center.present(request, action: .fileWrite, tier: .write) }
        while center.current == nil {
            await Task.yield()
        }
        #expect(center.current?.id == request.id)

        center.resolve(request.id, with: .allowed)

        #expect(await task.value == .allowed)
    }
}

/// The protocol carries no session identifier, so two sessions each raising
/// a request at the same time must not compete for the one prompt on
/// screen — https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#focus
@Suite("Approval prompt center: concurrent requests queue")
struct ApprovalPromptCenterQueueTests {
    @Test("A second request is queued and not shown until the first resolves")
    @MainActor
    func secondRequestWaitsBehindTheFirst() async {
        let center = ApprovalPromptCenter()
        let first = makeRequest(id: "first")
        let second = makeRequest(id: "second")

        let firstTask = Task { await center.present(first, action: .fileWrite, tier: .write) }
        while center.current == nil {
            await Task.yield()
        }

        let secondTask = Task { await center.present(second, action: .fileDelete, tier: .irreversible) }
        await Task.yield()
        #expect(center.current?.id == first.id)

        center.resolve(first.id, with: .denied)
        #expect(await firstTask.value == .denied)
        #expect(center.current?.id == second.id)

        center.resolve(second.id, with: .allowed)
        #expect(await secondTask.value == .allowed)
    }
}

/// "A gate that cannot obtain a decision denies" — cancellation is the one
/// case this conformance ends the wait on itself.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
@Suite("Approval prompt center: fails closed on cancellation")
struct ApprovalPromptCenterCancellationTests {
    @Test("Cancelling the waiting task resolves nil and clears the pending request")
    @MainActor
    func cancellationResolvesNilAndClearsCurrent() async {
        let center = ApprovalPromptCenter()
        let request = makeRequest()

        let task = Task { await center.present(request, action: .deployProduction, tier: .irreversible) }
        while center.current == nil {
            await Task.yield()
        }

        task.cancel()

        #expect(await task.value == nil)
        #expect(center.current == nil)
    }
}
