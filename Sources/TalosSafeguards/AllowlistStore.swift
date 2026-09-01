import Foundation
import TalosCore
import TalosProjectLibrary

/// Why an entry could not be accepted — at load, or on a write.
public enum AllowlistStoreError: Error, Equatable, Sendable {
    /// The file could not be read or written.
    case ioFailure(file: String, fix: String)
    /// `.talos/allowlist.yaml` failed to parse as YAML shape.
    case invalidShape(AllowlistManifestError)
    /// The name parsed, but is not an allowlistable action type.
    case invalidEntry(action: SafeguardsActionType, fix: String)
}

/// The concrete, per-project allowlist store: reads and writes
/// `.talos/allowlist.yaml`, and answers the gate's `isAllowlisted` query
/// against exact string equality with no caching layer to go stale.
///
/// One instance is scoped to one project by construction — `projectRoot`
/// names a single project's `.talos/` directory, and `isAllowlisted` refuses
/// any other ``ProjectIdentifier`` outright. There is no operation here that
/// takes more than one project or more than one action type, so a "global"
/// or "trust everything" allowlist has no shape to be expressed in.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
///
/// An `actor` rather than a struct: `allowlistAction` and
/// `revokeAllowlistedAction` mutate the same in-memory set `isAllowlisted`
/// reads, so a revoke and the next gated read on a running session are
/// serialized through the same actor and the revoke is visible immediately
/// — no session holds a stale copy to invalidate.
public actor AllowlistStore: SafeguardsAllowlist {
    private static let relativePath = ".talos/allowlist.yaml"

    private let project: ProjectIdentifier
    private let file: URL
    private let fileManager: FileManager
    private let changeLog: any AllowlistChangeLog
    private let now: @Sendable () -> Date
    private var allowlisted: Set<SafeguardsActionType>

    /// Loads `.talos/allowlist.yaml` under `projectRoot`, if present. A
    /// missing file is an empty allowlist, not an error — a project with no
    /// file yet has denied every write-tier action, which is deny-by-default
    /// rather than a defect to report.
    ///
    /// Every persisted entry is re-validated on load, not only on write: a
    /// name that became refused, dropped a tier, or was hand-edited into the
    /// file by a human is rejected here rather than trusted because it was
    /// already on disk.
    public init(
        projectRoot: URL,
        project: ProjectIdentifier,
        changeLog: any AllowlistChangeLog,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.project = project
        file = projectRoot.appendingPathComponent(Self.relativePath, isDirectory: false)
        self.fileManager = fileManager
        self.changeLog = changeLog
        self.now = now

        guard fileManager.fileExists(atPath: file.path) else {
            allowlisted = []
            return
        }

        let contents: String
        do {
            contents = try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw AllowlistStoreError.ioFailure(
                file: file.path, fix: "Fix '\(Self.relativePath)' so it can be read as UTF-8 text: \(error)"
            )
        }

        let manifest: AllowlistManifest
        do {
            manifest = try AllowlistManifestParser.parse(contents: contents, file: file.path)
        } catch let error as AllowlistManifestError {
            throw AllowlistStoreError.invalidShape(error)
        }

        var validated: Set<SafeguardsActionType> = []
        for rawEntry in manifest.entries {
            let action = SafeguardsActionType(rawValue: rawEntry)
            try Self.validateAllowlistable(action)
            validated.insert(action)
        }
        allowlisted = validated
    }

    /// The gate's read path. A project other than the one this store was
    /// constructed for is refused rather than looked up — there is no
    /// operation on this type that answers for a project it was not given at
    /// construction.
    public func isAllowlisted(_ action: SafeguardsActionType, project: ProjectIdentifier) async -> Bool {
        guard project == self.project else { return false }
        return allowlisted.contains(action)
    }

    /// Adds `action` to this project's allowlist, persists the change to
    /// disk, and logs it. Rejects an unknown name, a refused type, a
    /// read-tier type, and every irreversible-tier type — the same check
    /// `init` runs on load, so a name that could not have survived a fresh
    /// load cannot be written either.
    ///
    /// This is the only mutator that may grant an action, and it is never
    /// called from agent-facing code — asserted structurally by
    /// `AllowlistStoreWriteReachabilityTests`, since `config.allowlist.write`
    /// is refused outright rather than gated and has no approval path to
    /// reach this method through.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
    public func allowlistAction(_ action: SafeguardsActionType, actor: String) async throws {
        try Self.validateAllowlistable(action)
        allowlisted.insert(action)
        try persist()
        await changeLog.record(
            AllowlistChangeEntry(project: project, action: action, change: .added, actor: actor, timestamp: now())
        )
    }

    /// Removes `action` from this project's allowlist. A no-op, un-logged,
    /// when the action was never allowlisted — nothing changed, so nothing
    /// to persist or record.
    ///
    /// Takes effect immediately on a running session: `isAllowlisted` reads
    /// the same in-memory set this mutates, through the same actor, so the
    /// very next gated decision sees the revocation.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    public func revokeAllowlistedAction(_ action: SafeguardsActionType, actor: String) async throws {
        guard allowlisted.remove(action) != nil else { return }
        try persist()
        await changeLog.record(
            AllowlistChangeEntry(project: project, action: action, change: .removed, actor: actor, timestamp: now())
        )
    }

    private func persist() throws {
        let manifest = AllowlistManifest(entries: allowlisted.map(\.rawValue).sorted())
        let text = AllowlistManifestParser.serialize(manifest)
        do {
            try fileManager.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            throw AllowlistStoreError.ioFailure(
                file: file.path, fix: "Fix '\(Self.relativePath)' so it can be written: \(error)"
            )
        }
    }

    /// Only a write-tier name may be allowlisted: an unknown name is not in
    /// `taxonomy: 1` at all, a refused type has no approval path to begin
    /// with, a read-tier type is already always allowed, and an
    /// irreversible-tier type is "not allowlistable, ever."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
    private static func validateAllowlistable(_ action: SafeguardsActionType) throws {
        guard SafeguardsActionClassifier.knownActionTypes.contains(action) else {
            throw AllowlistStoreError.invalidEntry(
                action: action,
                fix: "'\(action.rawValue)' is not a name in taxonomy: 1. Use one of the registered action types."
            )
        }
        guard SafeguardsActionClassifier.classify(action) == .tier(.write) else {
            throw AllowlistStoreError.invalidEntry(
                action: action,
                fix: "'\(action.rawValue)' is not write-tier and can never be allowlisted."
            )
        }
    }
}
