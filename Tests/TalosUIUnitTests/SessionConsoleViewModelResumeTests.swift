import Foundation
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import TalosUI
import Testing

/// Verifies ``SessionConsoleViewModel/preload(_:decisions:)`` — "a prior
/// session can be resumed with its transcript and context intact."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Suite("Session console preload")
struct SessionConsoleViewModelResumeTests {
    @Test("A preloaded transcript reads as ready, with its output intact")
    @MainActor
    func preloadedOutputReadsAsReady() {
        let viewModel = SessionConsoleViewModel()

        viewModel.preload([.output("Reading the file tree.\n"), .output("Done.")], decisions: [])

        #expect(viewModel.state == .ready)
        #expect(viewModel.lines.map(\.outputPayload) == ["Reading the file tree.", "Done."])
    }

    @Test("A preloaded tool call with a matching decision reads back resolved")
    @MainActor
    func preloadedToolCallResolvesFromMatchingDecision() {
        let viewModel = SessionConsoleViewModel()
        let decision = Self.makeDecision(requestID: "t1", outcome: .allowed, tier: .write)

        viewModel.preload([.toolCall(id: "t1", name: "Write", targets: ["a.swift"])], decisions: [decision])

        guard case let .toolCall(call) = viewModel.lines.first?.content else {
            Issue.record("Expected one tool-call line")
            return
        }
        #expect(call.approval == .resolved(action: decision.action, tier: .write, outcome: .allowed))
    }

    @Test("A preloaded tool call with no matching decision reads back not gated")
    @MainActor
    func preloadedToolCallWithNoDecisionReadsBackNotGated() {
        let viewModel = SessionConsoleViewModel()

        viewModel.preload([.toolCall(id: "t1", name: "Read", targets: ["README.md"])], decisions: [])

        guard case let .toolCall(call) = viewModel.lines.first?.content else {
            Issue.record("Expected one tool-call line")
            return
        }
        #expect(call.approval == .notGated)
    }

    /// A refused classification has no tier of its own — it never understates
    /// the row by falling back to `.read`.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
    @Test("A refused decision renders at the irreversible tier, never understated")
    @MainActor
    func refusedDecisionRendersAtIrreversibleTier() {
        let viewModel = SessionConsoleViewModel()
        let decision = Self.makeDecision(requestID: "t1", outcome: .denied, classification: .refused)

        viewModel.preload([.toolCall(id: "t1", name: "Send", targets: ["secret"])], decisions: [decision])

        guard case let .toolCall(call) = viewModel.lines.first?.content else {
            Issue.record("Expected one tool-call line")
            return
        }
        #expect(call.approval == .resolved(action: decision.action, tier: .irreversible, outcome: .denied))
    }

    private static func makeDecision(
        requestID: String,
        outcome: AgentPermissionDecision,
        tier: SafeguardsTier = .write,
        classification: SafeguardsClassification? = nil
    ) -> StoredGatedDecisionEntry {
        StoredGatedDecisionEntry(
            id: 1,
            project: ProjectIdentifier(rawValue: "p1"),
            sessionID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1000),
            subFunction: .assistant,
            requestID: requestID,
            requestPrompt: "Do the thing.",
            action: SafeguardsActionType(rawValue: "file.write"),
            classification: classification ?? .tier(tier),
            actor: .user,
            outcome: outcome
        )
    }
}
