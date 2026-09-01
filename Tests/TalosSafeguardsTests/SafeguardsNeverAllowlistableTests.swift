import Foundation
import TalosCore
import TalosProjectLibrary
@testable import TalosSafeguards
import Testing

/// Verifies the compiled-in never-allowlistable registry: exact membership,
/// that it never claims a name softer than irreversible tier, and that it
/// carries no I/O to go stale.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
@Suite("Never-allowlistable registry")
struct SafeguardsNeverAllowlistableTests {
    // MARK: - AC: the registry enumerates exactly the eight SPEC items, by taxonomy name

    @Test("The registry holds exactly the eleven taxonomy names carrying one of the eight SPEC items")
    func registryHoldsExactlyTheNamedTypes() {
        let expected: Set<SafeguardsActionType> = [
            .gitPushForce, .gitHistoryRewrite,
            .gitBranchDelete, .gitRepoDelete,
            .secretRead, .secretWrite, .secretSend,
            .deployProduction,
            .spendPaid,
            .packagePublish,
            .connectorUndeclared
        ]

        #expect(SafeguardsNeverAllowlistable.registry == expected)
        #expect(SafeguardsNeverAllowlistable.registry.count == 11)
    }

    // MARK: - AC: every other irreversible-tier type is equally unallowlistable, not only the 🔒 ones

    @Test(
        "Every registry member classifies as irreversible tier",
        arguments: [
            SafeguardsActionType.gitPushForce, .gitHistoryRewrite, .gitBranchDelete, .gitRepoDelete,
            .secretRead, .secretWrite, .secretSend, .deployProduction, .spendPaid, .packagePublish,
            .connectorUndeclared
        ]
    )
    func everyRegistryMemberIsIrreversibleTier(action: SafeguardsActionType) {
        #expect(SafeguardsActionClassifier.classify(action) == .tier(.irreversible))
    }

    @Test("The registry is a strict subset of the irreversible tier — other irreversible types exist outside it")
    func registryIsAStrictSubsetOfIrreversibleTier() {
        let irreversible = SafeguardsActionClassifier.knownActionTypes.filter {
            SafeguardsActionClassifier.classify($0) == .tier(.irreversible)
        }
        #expect(SafeguardsNeverAllowlistable.registry.isStrictSubset(of: irreversible))
    }

    // MARK: - AC: compiled in, not read from disk

    @Test("Reading the registry twice returns the same value — no I/O, no hidden state")
    func registryIsPure() {
        let firstRead = SafeguardsNeverAllowlistable.registry
        let secondRead = SafeguardsNeverAllowlistable.registry
        #expect(firstRead == secondRead)
    }

    // MARK: - AC: attempting to allowlist a never-allowlistable action cites the SPEC rule

    private actor RecordingChangeLog: AllowlistChangeLog {
        func record(_ entry: AllowlistChangeEntry) async {
            _ = entry
        }
    }

    private static func makeTemporaryProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafeguardsNeverAllowlistableTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test(
        "Every registry member's rejection message quotes the never-allowlistable SPEC line",
        arguments: [
            SafeguardsActionType.gitPushForce, .gitHistoryRewrite, .gitBranchDelete, .gitRepoDelete,
            .secretRead, .secretWrite, .secretSend, .deployProduction, .spendPaid, .packagePublish,
            .connectorUndeclared
        ]
    )
    func registryMemberRejectionCitesSpecRule(action: SafeguardsActionType) async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
        )

        await #expect {
            try await store.allowlistAction(action, actor: "user")
        } throws: { error in
            guard case let .invalidEntry(_, fix) = error as? AllowlistStoreError else { return false }
            return fix.contains(
                "No configuration, no user preference, and no agent request can move these out of " +
                    "in-the-moment approval"
            )
        }
    }

    @Test("A non-registry irreversible type's rejection message does not quote the never-allowlistable line")
    func nonRegistryIrreversibleRejectionDoesNotCiteSpecRule() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
        )

        await #expect {
            try await store.allowlistAction(.processRun, actor: "user")
        } throws: { error in
            guard case let .invalidEntry(_, fix) = error as? AllowlistStoreError else { return false }
            return !fix.contains("No configuration, no user preference")
        }
    }
}
