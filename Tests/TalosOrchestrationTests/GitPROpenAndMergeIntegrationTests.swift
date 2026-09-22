import Foundation
import TalosAdapters
import TalosCore
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// The opt-in, local-only live proof for MVP DoD item 5's PR half — see
/// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done
/// a real PR is opened with the Safeguards gate firing on
/// each git operation, and a denied merge leaves nothing merged. It runs the
/// developer's own `gh`/`git` against a scratch repo — so it needs a CLI, a
/// credential, and the network, which the default suite forbids. It is
/// therefore **disabled unless `TALOS_GH_INTEGRATION=1`** and skipped in CI,
/// the one opt-in lane the git-recognition decision carves out of
/// [decisions 34/49/93](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log).
///
/// Set `TALOS_GH_INTEGRATION_REPO=<owner>/<repo>` to a throwaway repo you can
/// open and close PRs on. The test clones it, opens a real PR through the gate,
/// denies a real merge, asserts the PR is still open, then closes the PR and
/// deletes the branch.
@Suite("Git PR open and merge, live gh integration (opt-in)")
struct GitPROpenAndMergeIntegrationTests {
    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TALOS_GH_INTEGRATION"] == "1"
    }

    private static var scratchRepo: String {
        ProcessInfo.processInfo.environment["TALOS_GH_INTEGRATION_REPO"] ?? ""
    }

    @Test(
        "The gate fires on a real PR open, then a denied merge leaves nothing merged",
        .enabled(if: isEnabled)
    )
    func realPROpenAndDeniedMerge() async throws {
        let repo = try #require(!Self.scratchRepo.isEmpty ? Self.scratchRepo : nil, "Set TALOS_GH_INTEGRATION_REPO")
        let workspace = try TemporaryWorkspace(cloning: repo)
        defer { workspace.cleanUp() }

        let branch = try workspace.commitMarkerOnNewBranch()

        // The scratch repo is the declared system, so a git op reaching it
        // resolves to its specific taxonomy type rather than connector.undeclared.
        let connectors = ConnectorsManifest(connectors: [
            ConnectorDeclaration(
                name: "scratch", kind: .repo,
                target: "https://github.com/\(repo)", reachedVia: .cli
            )
        ])

        // Approve the push and the PR open; the gate must fire on each.
        let approveGate = TieredSafeguardsGate(
            allowlist: DenyingAllowlist(), approvalPrompt: FixedDecisionPrompt(.allowed), connectors: connectors
        )
        let project = ProjectIdentifier.generate()

        let pushDecision = await approveGate.decide(
            gitRequest(.gitPush, isRepoRemote: true), project: project, subFunction: .automator
        )
        #expect(pushDecision.action == .gitPush)
        #expect(pushDecision.outcome == .allowed)
        try workspace.run("git", "push", "-u", "origin", branch)

        let openDecision = await approveGate.decide(
            gitRequest(.gitPROpen, isRepoRemote: true), project: project, subFunction: .automator
        )
        #expect(openDecision.action == .gitPROpen)
        #expect(openDecision.outcome == .allowed)
        let prNumber = try workspace.output("gh", "pr", "create", "--fill", "--head", branch)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!prNumber.isEmpty)

        defer {
            _ = try? workspace.run("gh", "pr", "close", prNumber)
            _ = try? workspace.run("git", "push", "origin", "--delete", branch)
        }

        // Deny the merge. It is irreversible, and a denied merge must not run.
        let denyGate = TieredSafeguardsGate(
            allowlist: DenyingAllowlist(), approvalPrompt: FixedDecisionPrompt(.denied), connectors: connectors
        )
        let mergeDecision = await denyGate.decide(
            gitRequest(.gitPRMerge, isRepoRemote: true), project: project, subFunction: .automator
        )
        #expect(mergeDecision.action == .gitPRMerge)
        #expect(mergeDecision.classification == .tier(.irreversible))
        #expect(mergeDecision.outcome == .denied)
        // The denial means `gh pr merge` is never run — nothing is merged. The
        // PR's own state is the ground truth.
        let state = try workspace.output("gh", "pr", "view", prNumber, "--json", "state", "-q", ".state")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(state == "OPEN")
    }

    private func gitRequest(_ action: SafeguardsActionType, isRepoRemote: Bool) -> AgentPermissionRequest {
        AgentPermissionRequest(
            id: UUID().uuidString,
            prompt: action.rawValue,
            connectorAccess: isRepoRemote ? AgentConnectorAccess(target: "", verb: .write, isRepoRemote: true) : nil,
            classifiedAction: action
        )
    }
}

// MARK: - Doubles and a process helper, local to this opt-in suite

private actor DenyingAllowlist: SafeguardsAllowlist {
    func isAllowlisted(_: SafeguardsActionType, project _: ProjectIdentifier) async -> Bool {
        false
    }
}

private actor FixedDecisionPrompt: SafeguardsApprovalPrompt {
    private let decision: AgentPermissionDecision
    init(_ decision: AgentPermissionDecision) {
        self.decision = decision
    }

    func present(
        _: AgentPermissionRequest, action _: SafeguardsActionType, tier _: SafeguardsTier
    ) async -> AgentPermissionDecision? {
        decision
    }
}

/// A cloned scratch repo in a temp directory. The test — standing in for the
/// agent that would run these commands — shells out to real `git`/`gh`; this is
/// a test harness, not Talos core, so it does not cross the orchestration
/// boundary.
private struct TemporaryWorkspace {
    let directory: URL

    init(cloning repo: String) throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("talos-gh-e2e-\(UUID().uuidString)", isDirectory: true)
        try Self.execute("gh", ["repo", "clone", repo, directory.path], cwd: nil)
    }

    /// Creates a unique branch with one marker commit, returning the branch name.
    func commitMarkerOnNewBranch() throws -> String {
        let suffixLength = 8
        let branch = "talos-e2e-\(UUID().uuidString.prefix(suffixLength))"
        try run("git", "checkout", "-b", branch)
        let file = directory.appendingPathComponent("TALOS_E2E_MARKER.md")
        try "Talos live integration marker \(Date())\n".write(to: file, atomically: true, encoding: .utf8)
        try run("git", "add", "-A")
        try run(
            "git", "-c", "user.email=e2e@talos.test", "-c", "user.name=Talos E2E",
            "commit", "-m", "Talos E2E marker"
        )
        return branch
    }

    @discardableResult
    func run(_ arguments: String...) throws -> String {
        try Self.execute(arguments[0], Array(arguments.dropFirst()), cwd: directory)
    }

    func output(_ arguments: String...) throws -> String {
        try Self.execute(arguments[0], Array(arguments.dropFirst()), cwd: directory)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private static func execute(_ tool: String, _ arguments: [String], cwd: URL?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        if let cwd {
            process.currentDirectoryURL = cwd
        }
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw IntegrationError.commandFailed(
                tool: tool, arguments: arguments, status: process.terminationStatus, output: text
            )
        }
        return text
    }

    enum IntegrationError: Error {
        case commandFailed(tool: String, arguments: [String], status: Int32, output: String)
    }
}
