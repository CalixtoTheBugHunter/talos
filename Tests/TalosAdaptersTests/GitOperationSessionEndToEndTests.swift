import Foundation
@testable import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// The fixture-driven end-to-end proof for git operation gating, at the level [the suite installs
/// nothing](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing)
/// allows — the live "opens a real PR" proof is the opt-in
/// `GitPROpenAndMergeIntegrationTests`. It runs the same real pipeline as
/// ``AssistantSessionEndToEndTests`` (real ``ClaudeCodeAdapter``,
/// ``TieredSafeguardsGate``, ``SafeguardsActionClassifier``), reusing that
/// suite's project, doubles, and `makePipeline`.
@Suite("Git operation session, end to end")
struct GitOperationSessionEndToEndTests {
    /// AC9: a `gh pr create` the agent runs through `Bash` is recognized as
    /// `git.pr.open`, fires the gate at its write tier against a declared repo,
    /// and — approved — the session proceeds.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done
    @Test("A gh pr create is recognized as git.pr.open and fires the gate at write tier")
    func prOpenFiresTheGateAtWriteTier() async throws {
        let project = try AssistantEndToEndProject.makeWithRepoConnector()
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let launch = SessionLaunch(
            agentName: "claude-code",
            configuration: ClaudeCodeFakeExecutable.configuration(
                launchResponse: ClaudeCodeFixture.path("git-pr-open.jsonl"),
                resumeResponse: ClaudeCodeFixture.path("token-report.jsonl")
            )
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let approvalPrompt = RecordingApprovalPrompt(outcome: .allowed)
        let decisionLog = RecordingGatedDecisionLog()
        let pipeline = AssistantSessionEndToEndTests.makePipeline(
            adapter: adapter, approvalPrompt: approvalPrompt, decisionLog: decisionLog, connectors: project.connectors
        )

        let record = await pipeline.run(
            intent: project.intent(content: "Open a PR for the change."),
            guideline: project.guideline,
            safeguards: project.safeguards,
            connectors: project.connectors,
            launch: launch
        )

        guard case .succeeded = record.outcome else {
            Issue.record("Expected the resumed session to succeed, got \(record.outcome)")
            return
        }
        let presented = await approvalPrompt.presented
        #expect(presented.count == 1)
        #expect(presented.first?.action == .gitPROpen)
        #expect(presented.first?.tier == .write)
        let logged = await decisionLog.entries
        #expect(logged.map(\.outcome) == [.allowed])
        #expect(logged.map(\.action) == [.gitPROpen])
    }

    /// AC10: a `gh pr merge` is recognized as `git.pr.merge`, gates at the
    /// irreversible tier, and a denial leaves nothing merged — the merge command
    /// is answered deny and never resolved, and the session continues. "Anyone
    /// can build an automator that works when you say yes"; saying no is the
    /// real test.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria
    @Test("A denied gh pr merge is git.pr.merge, irreversible, and nothing is merged")
    func prMergeDeniedLeavesNothingMerged() async throws {
        let project = try AssistantEndToEndProject.makeWithRepoConnector()
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let launch = SessionLaunch(
            agentName: "claude-code",
            configuration: ClaudeCodeFakeExecutable.configuration(
                launchResponse: ClaudeCodeFixture.path("git-pr-merge.jsonl"),
                resumeResponse: ClaudeCodeFixture.path("token-report.jsonl")
            )
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let approvalPrompt = RecordingApprovalPrompt(outcome: .denied)
        let decisionLog = RecordingGatedDecisionLog()
        let pipeline = AssistantSessionEndToEndTests.makePipeline(
            adapter: adapter, approvalPrompt: approvalPrompt, decisionLog: decisionLog, connectors: project.connectors
        )

        let record = await pipeline.run(
            intent: project.intent(content: "Merge the PR."),
            guideline: project.guideline,
            safeguards: project.safeguards,
            connectors: project.connectors,
            launch: launch
        )

        guard case .succeeded = record.outcome else {
            Issue.record("Expected the resumed session to succeed, got \(record.outcome)")
            return
        }
        #expect(record.denialCount == 1)
        let presented = await approvalPrompt.presented
        #expect(presented.count == 1)
        #expect(presented.first?.action == .gitPRMerge)
        #expect(presented.first?.tier == .irreversible)
        let logged = await decisionLog.entries
        #expect(logged.map(\.outcome) == [.denied])
        #expect(logged.map(\.action) == [.gitPRMerge])
    }
}
