import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import Testing

/// The CI assertion behind the < 5% Talos-added token overhead release gate:
/// a representative session, assembled by the real ``ContextAssembler`` and
/// measured by the same arithmetic the Monitor uses, stays under the budget.
/// `perf-budget` runs this suite by name.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
@Suite("Token overhead budget")
struct TokenOverheadBudgetTests {
    /// A real Automator-style request: a short instruction, a pasted crash log,
    /// every droppable part the guideline asks for, and an agent turn that
    /// reads the log, uses tools, and writes a change.
    @Test("A representative session stays under 5% of the agent's session tokens")
    func representativeSessionStaysUnderBudget() throws {
        let pastedLog = String(repeating: "at com.example.Widget.render(Widget.java:42)\n", count: 200)
        let input = ContextAssemblyInput(
            intent: makeTestIntent(content: "Here is the crash log, please fix it:\n\(pastedLog)"),
            guideline: makeTestGuideline(
                context: ["spec-drive", "board", "memories", "connectors"],
                tokenCeiling: 4000,
                rawText: "Carry out a requested change under the Safeguards gate."
            ),
            safeguards: makeTestSafeguards(rawText: "Never deploy on a Friday. Always run tests first."),
            connectors: ConnectorsManifest(connectors: [
                ConnectorDeclaration(name: "repo", kind: .repo, target: "https://example.com/repo", reachedVia: .cli)
            ])
        )
        guard case let .assembled(assembled) = makeTestAssembler().assemble(input) else {
            Issue.record("Expected assembly to succeed")
            return
        }

        // The agent's own account: it read the prompt Talos sent (the raw
        // request plus what Talos injected) and produced a multi-step turn.
        let reportedInput = assembled.rawPromptTokenEstimate + assembled.injectedTokens.total
        let agentOutput = 6000
        let overhead = try #require(SessionOverhead(
            injected: assembled.injectedTokens,
            report: .measured(TokenCounts(input: reportedInput, output: agentOutput), model: "test-model")
        ))

        #expect(overhead.exceedsBudget == false)
        #expect(overhead.ratio < 0.05)
    }
}
