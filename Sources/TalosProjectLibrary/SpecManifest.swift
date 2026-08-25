import Foundation

// The typed model for `.talos/spec.yaml` — the Spec Drive location(s) and
// their sync rules. Absence of a Spec Drive is a declared state, never an
// empty or missing key.
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-project-has-no-spec-drive
//
// https://github.com/CalixtoTheBugHunter/talos/issues/44

/// The registered Spec Drive providers. GitHub Wikis is the only one at MVP,
/// per [decision 36](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions) —
/// a local-directory kind is explicitly ruled out, because a spec location
/// only Talos knows about is a second source of truth nobody outside Talos
/// maintains. `SpecManifestParser` validates a `provider:` name against this
/// set; a second provider (Confluence, per
/// [Project Library § Spec Drive](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive))
/// is added here without touching any other part of Talos.
public enum SpecDriveProviderKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case githubWiki = "github-wiki"
}

/// Whether Talos may edit this location, or only read it. At minimum the two
/// states [Project Library § Spec Drive](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive)
/// requires: "Talos may edit the specs when the user decides it should."
public enum SpecDriveSyncRule: String, Equatable, Hashable, Sendable {
    case readOnly = "read-only"
    case talosMayEdit = "talos-may-edit"
}

/// One declared Spec Drive location.
public struct SpecDriveLocation: Equatable, Sendable {
    public let provider: SpecDriveProviderKind
    public let url: String
    public let syncRule: SpecDriveSyncRule

    public init(provider: SpecDriveProviderKind, url: String, syncRule: SpecDriveSyncRule) {
        self.provider = provider
        self.url = url
        self.syncRule = syncRule
    }
}

/// Whether a Spec Drive item is DRAFT — work planned for the future — or
/// published, per
/// [Project Library § Spec Drive](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive):
/// "Specs also contain DRAFT items... so Talos can proactively scale the
/// application toward them." Declared here as the domain vocabulary a Spec
/// Drive item carries; it is not parsed from `spec.yaml` and holds no
/// content — populating it is
/// [Spec Drive indexing and retrieval](https://github.com/CalixtoTheBugHunter/talos/issues/82),
/// which this issue explicitly does not do.
public enum SpecItemStatus: Equatable, Hashable, Sendable {
    case draft
    case published
}

/// The project's Spec Drive: either declared **absent**, or one or more
/// declared locations. `.absent` is a state this type can hold, never the
/// consequence of a missing or empty `spec.yaml` key — a missing key is a
/// ``SpecManifestError`` from ``SpecManifestParser``, not this case.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-project-has-no-spec-drive
public enum SpecDrive: Equatable, Sendable {
    case absent
    case locations([SpecDriveLocation])
}

/// The parsed, validated contents of `.talos/spec.yaml`.
public struct SpecManifest: Equatable, Sendable {
    public let specDrive: SpecDrive

    public init(specDrive: SpecDrive) {
        self.specDrive = specDrive
    }
}

/// A validation failure that names the file, the line, and the fix — the
/// same shape ``ProjectManifestError`` and ``AgentsManifestError`` use.
public struct SpecManifestError: Error, Equatable, Sendable {
    /// The path of the file that failed to parse or validate.
    public let file: String
    /// The 1-indexed source line the failure was found at, when the YAML
    /// parser could locate one.
    public let line: Int?
    /// What to change to fix it, stated as an instruction.
    public let fix: String
}
