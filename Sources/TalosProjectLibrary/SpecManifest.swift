import Foundation

/// The registered Spec Drive providers. Only `github-wiki` is valid at
/// MVP — a local directory is not, since a spec location only Talos knows
/// about is a second source of truth nobody else maintains.
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

/// One Spec Drive location declared in spec.yaml; a project may declare several, each with its own sync rule.
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

/// Whether a Spec Drive item is planned (`draft`) or `published`. Declared
/// here as domain vocabulary only — not yet parsed from `spec.yaml` or
/// populated from indexed content.
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

/// The parsed, validated contents of `.talos/spec.yaml`. Absence of a Spec
/// Drive is a declared state, never an empty or missing key.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive
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
