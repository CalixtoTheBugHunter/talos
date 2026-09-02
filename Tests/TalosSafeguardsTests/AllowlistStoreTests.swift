import Foundation
import TalosCore
import TalosProjectLibrary
@testable import TalosSafeguards
import Testing

/// Verifies the per-project, per-action-type allowlist store: exact-match
/// scoping, taxonomy validation, and the audit trail a change leaves.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
@Suite("Allowlist store")
struct AllowlistStoreTests {
    /// Records every entry it was asked to log, so a test can assert actor
    /// and timestamp without a durable log implementation.
    private actor RecordingChangeLog: AllowlistChangeLog {
        private(set) var entries: [AllowlistChangeEntry] = []

        func record(_ entry: AllowlistChangeEntry) async {
            entries.append(entry)
        }
    }

    private static func makeTemporaryProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AllowlistStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func writeAllowlistFile(contents: String, under root: URL) throws {
        let talosDirectory = root.appendingPathComponent(".talos", isDirectory: true)
        try FileManager.default.createDirectory(at: talosDirectory, withIntermediateDirectories: true)
        let file = talosDirectory.appendingPathComponent("allowlist.yaml", isDirectory: false)
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - AC: entries are scoped to one project and one action type

    /// A store's file is derived from `projectRoot` alone, so the guarantee two
    /// *different* stores never share an entry only holds for two different
    /// roots — which is the only case that occurs in practice, since a
    /// project's `.talos/` lives under that project's own repository root.
    /// This is deliberately two separate roots rather than one shared root
    /// with two `ProjectIdentifier`s: the latter would be two stores reading
    /// the same file by construction, which is not a scoping failure this
    /// type is responsible for guarding — it is a caller passing a
    /// `projectRoot` that does not belong to the `project` it named.
    @Test("Two projects, with separate project roots, never share an entry")
    func twoProjectsWithSeparateRootsDoNotShareEntries() async throws {
        let rootA = try Self.makeTemporaryProjectRoot()
        let rootB = try Self.makeTemporaryProjectRoot()
        let projectA = ProjectIdentifier(rawValue: "project-a")
        let projectB = ProjectIdentifier(rawValue: "project-b")
        let storeA = try AllowlistStore(projectRoot: rootA, project: projectA, changeLog: RecordingChangeLog())
        let storeB = try AllowlistStore(projectRoot: rootB, project: projectB, changeLog: RecordingChangeLog())

        try await storeA.allowlistAction(.fileWrite, actor: "user")

        #expect(await storeA.isAllowlisted(.fileWrite, project: projectA))
        #expect(await !storeB.isAllowlisted(.fileWrite, project: projectB))
    }

    @Test("isAllowlisted refuses to answer for a project other than the one this store was constructed for")
    func isAllowlistedRefusesAnotherProject() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let projectA = ProjectIdentifier(rawValue: "project-a")
        let projectB = ProjectIdentifier(rawValue: "project-b")
        let store = try AllowlistStore(projectRoot: root, project: projectA, changeLog: RecordingChangeLog())

        try await store.allowlistAction(.fileWrite, actor: "user")

        #expect(await store.isAllowlisted(.fileWrite, project: projectA))
        #expect(await !store.isAllowlisted(.fileWrite, project: projectB))
    }

    @Test("A missing allowlist.yaml is an empty allowlist, not an error")
    func missingFileIsAnEmptyAllowlist() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
        )

        #expect(await !store.isAllowlisted(.fileWrite, project: ProjectIdentifier(rawValue: "p")))
    }

    // MARK: - AC: an unknown name is rejected rather than stored and silently never matched

    @Test("Loading a file with an unrecognized action type name throws")
    func loadingUnrecognizedNameThrows() throws {
        let root = try Self.makeTemporaryProjectRoot()
        try Self.writeAllowlistFile(contents: "allowlist:\n  - not.a.real.type\n", under: root)

        #expect {
            try AllowlistStore(
                projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
            )
        } throws: { error in
            guard case let .invalidEntry(action, _) = error as? AllowlistStoreError else { return false }
            return action.rawValue == "not.a.real.type"
        }
    }

    @Test("Writing an unrecognized action type name throws")
    func writingUnrecognizedNameThrows() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
        )

        await #expect {
            try await store.allowlistAction(SafeguardsActionType(rawValue: "not.a.real.type"), actor: "user")
        } throws: { error in
            guard case let .invalidEntry(action, _) = error as? AllowlistStoreError else { return false }
            return action.rawValue == "not.a.real.type"
        }
    }

    // MARK: - AC: prefix, wildcard, and pattern entries are unrepresentable

    @Test("A wildcard-shaped entry is rejected as an unrecognized name, not matched as a pattern")
    func wildcardShapedEntryIsRejected() throws {
        let root = try Self.makeTemporaryProjectRoot()
        try Self.writeAllowlistFile(contents: "allowlist:\n  - \"git.*\"\n", under: root)

        #expect {
            try AllowlistStore(
                projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
            )
        } throws: { error in
            guard case let .invalidEntry(action, _) = error as? AllowlistStoreError else { return false }
            return action.rawValue == "git.*"
        }
    }

    // MARK: - AC: matching is exact string equality

    @Test("An entry for git.push does not match git.push.protected")
    func exactMatchDoesNotMatchAQualifiedName() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let project = ProjectIdentifier(rawValue: "p")
        let store = try AllowlistStore(projectRoot: root, project: project, changeLog: RecordingChangeLog())

        try await store.allowlistAction(.gitPush, actor: "user")

        #expect(await store.isAllowlisted(.gitPush, project: project))
        #expect(await !store.isAllowlisted(.gitPushProtected, project: project))
    }

    // MARK: - AC: never-allowlistable actions are rejected at the store layer

    @Test(
        "Every irreversible-tier action type is rejected when writing",
        arguments: [
            SafeguardsActionType.processRun, .fileDelete, .gitPushProtected, .gitPushForce, .gitHistoryRewrite,
            .gitBranchDelete, .gitRepoDelete, .gitPRMerge, .boardItemDelete, .specDelete, .specDriveCreate,
            .secretRead, .secretWrite, .secretSend, .deployStaging, .deployProduction, .packageInstall,
            .packagePublish, .spendPaid, .connectorUndeclared
        ]
    )
    func everyIrreversibleActionTypeIsRejected(action: SafeguardsActionType) async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
        )

        await #expect {
            try await store.allowlistAction(action, actor: "user")
        } throws: { error in
            guard case let .invalidEntry(rejected, _) = error as? AllowlistStoreError else { return false }
            return rejected == action
        }
    }

    // MARK: - AC: hand-editing the config file directly is rejected too, not only the API write

    /// The API write path above (`everyIrreversibleActionTypeIsRejected`) is one way an entry could
    /// reach the store — the config-file path is a different one: an actor with plain file-write
    /// access edits `.talos/allowlist.yaml` by hand rather than calling `allowlistAction`. `init`
    /// re-validates every loaded entry the same way, so this is the same rejection reached through
    /// the file rather than the API — checked here against a real never-allowlistable name, not only
    /// against the unrecognized-name and wildcard-shaped fixtures the tests above already cover.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
    @Test(
        "Hand-editing allowlist.yaml to add a never-allowlistable action throws on load",
        arguments: SafeguardsNeverAllowlistable.registry
    )
    func handEditedNeverAllowlistableEntryThrowsOnLoad(action: SafeguardsActionType) throws {
        let root = try Self.makeTemporaryProjectRoot()
        try Self.writeAllowlistFile(contents: "allowlist:\n  - \(action.rawValue)\n", under: root)

        #expect {
            try AllowlistStore(
                projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
            )
        } throws: { error in
            guard case let .invalidEntry(rejected, _) = error as? AllowlistStoreError else { return false }
            return rejected == action
        }
    }

    @Test("A read-tier action type is rejected — it never needs allowlisting")
    func readTierActionTypeIsRejected() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
        )

        await #expect {
            try await store.allowlistAction(.fileRead, actor: "user")
        } throws: { error in
            guard case let .invalidEntry(action, _) = error as? AllowlistStoreError else { return false }
            return action == .fileRead
        }
    }

    // MARK: - AC: the three refused types are rejected too

    @Test(
        "Every refused action type is rejected when writing, config.allowlist.write included",
        arguments: [SafeguardsActionType.configSafeguardsWrite, .configAllowlistWrite, .configTierWrite]
    )
    func everyRefusedActionTypeIsRejected(action: SafeguardsActionType) async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: RecordingChangeLog()
        )

        await #expect {
            try await store.allowlistAction(action, actor: "user")
        } throws: { error in
            guard case let .invalidEntry(rejected, _) = error as? AllowlistStoreError else { return false }
            return rejected == action
        }
    }

    // MARK: - AC: allowlist changes are logged with actor and timestamp

    @Test("Allowlisting an action logs it with the actor and a timestamp")
    func allowlistingLogsActorAndTimestamp() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let project = ProjectIdentifier(rawValue: "p")
        let changeLog = RecordingChangeLog()
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let store = try AllowlistStore(
            projectRoot: root, project: project, changeLog: changeLog, now: { fixedNow }
        )

        try await store.allowlistAction(.fileWrite, actor: "paulo")

        let entries = await changeLog.entries
        #expect(entries.count == 1)
        #expect(entries.first?.project == project)
        #expect(entries.first?.action == .fileWrite)
        #expect(entries.first?.change == .added)
        #expect(entries.first?.actor == "paulo")
        #expect(entries.first?.timestamp == fixedNow)
    }

    @Test("Revoking an action logs it as removed, with the actor and a timestamp")
    func revokingLogsActorAndTimestamp() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let project = ProjectIdentifier(rawValue: "p")
        let changeLog = RecordingChangeLog()
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let store = try AllowlistStore(
            projectRoot: root, project: project, changeLog: changeLog, now: { fixedNow }
        )
        try await store.allowlistAction(.fileWrite, actor: "paulo")

        try await store.revokeAllowlistedAction(.fileWrite, actor: "paulo")

        let entries = await changeLog.entries
        #expect(entries.count == 2)
        #expect(entries.last?.change == .removed)
        #expect(entries.last?.actor == "paulo")
        #expect(entries.last?.timestamp == fixedNow)
    }

    @Test("Revoking an action that was never allowlisted is a silent no-op, not logged")
    func revokingAnUnallowlistedActionIsANoOp() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let changeLog = RecordingChangeLog()
        let store = try AllowlistStore(
            projectRoot: root, project: ProjectIdentifier(rawValue: "p"), changeLog: changeLog
        )

        try await store.revokeAllowlistedAction(.fileWrite, actor: "paulo")

        #expect(await changeLog.entries.isEmpty)
    }

    // MARK: - AC: revoking takes effect immediately on a running session

    @Test("Revoking an allowlisted action is reflected by the very next isAllowlisted call")
    func revokingTakesImmediateEffect() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let project = ProjectIdentifier(rawValue: "p")
        let store = try AllowlistStore(projectRoot: root, project: project, changeLog: RecordingChangeLog())
        try await store.allowlistAction(.fileWrite, actor: "user")
        #expect(await store.isAllowlisted(.fileWrite, project: project))

        try await store.revokeAllowlistedAction(.fileWrite, actor: "user")

        #expect(await !store.isAllowlisted(.fileWrite, project: project))
    }

    // MARK: - Persistence: a change survives a reload, and no other project's file is touched

    @Test("An allowlisted action persists to disk and is loaded back by a fresh store")
    func allowlistedActionPersistsAcrossReload() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let project = ProjectIdentifier(rawValue: "p")
        let firstStore = try AllowlistStore(projectRoot: root, project: project, changeLog: RecordingChangeLog())
        try await firstStore.allowlistAction(.fileWrite, actor: "user")

        let secondStore = try AllowlistStore(projectRoot: root, project: project, changeLog: RecordingChangeLog())

        #expect(await secondStore.isAllowlisted(.fileWrite, project: project))
    }

    @Test("A revoked action is absent from a fresh store loaded after the revoke")
    func revokedActionIsAbsentAfterReload() async throws {
        let root = try Self.makeTemporaryProjectRoot()
        let project = ProjectIdentifier(rawValue: "p")
        let firstStore = try AllowlistStore(projectRoot: root, project: project, changeLog: RecordingChangeLog())
        try await firstStore.allowlistAction(.fileWrite, actor: "user")
        try await firstStore.revokeAllowlistedAction(.fileWrite, actor: "user")

        let secondStore = try AllowlistStore(projectRoot: root, project: project, changeLog: RecordingChangeLog())

        #expect(await !secondStore.isAllowlisted(.fileWrite, project: project))
    }
}
