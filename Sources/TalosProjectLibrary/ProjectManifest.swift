import Foundation

/// A stable, immutable project identifier. Never derived from a mutable path
/// or repo name — ``generate()`` is the only constructor for a fresh one, so
/// nothing in Talos can accidentally compute one from something that moves.
public struct ProjectIdentifier: RawRepresentable, Equatable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// A freshly generated identifier, independent of any path or repo name.
    public static func generate() -> Self {
        Self(rawValue: UUID().uuidString)
    }
}

/// The four sub-functions `project.yaml` may enable, named exactly as the
/// scaffolded `guidelines/*.md` files name them. `.advisor` and
/// `.selfImprover` are recognized here even though both are "Coming soon" —
/// this model only parses the declaration; it does not act on it.
public enum SubFunction: String, CaseIterable, Equatable, Hashable, Sendable {
    case assistant
    case automator
    case advisor
    case selfImprover = "self-improver"
}

/// A YAML value this module does not recognize, held exactly as read so it
/// can be written back unchanged. Deliberately Yams-free — this is the type
/// the rest of Talos sees, so parsing this file never requires depending on
/// the YAML library beyond ``ProjectManifestParser``.
public indirect enum TalosYAMLValue: Equatable, Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case null
    case array([Self])
    case map([String: Self])
}

/// The parsed, validated contents of `.talos/project.yaml`.
///
/// `unknownTopLevelKeys` is what makes rewriting this file non-destructive:
/// a key this version of Talos does not recognize — from a newer Talos or a
/// human edit — round-trips through parse and serialize unchanged rather
/// than being silently discarded.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
public struct ProjectManifest: Equatable, Sendable {
    public let id: ProjectIdentifier
    public let configuredAgents: [String]
    public let subFunctions: [SubFunction: Bool]
    public let unknownTopLevelKeys: [String: TalosYAMLValue]

    public init(
        id: ProjectIdentifier,
        configuredAgents: [String],
        subFunctions: [SubFunction: Bool],
        unknownTopLevelKeys: [String: TalosYAMLValue] = [:]
    ) {
        self.id = id
        self.configuredAgents = configuredAgents
        self.subFunctions = subFunctions
        self.unknownTopLevelKeys = unknownTopLevelKeys
    }
}

/// A validation failure that names the file, the line, and the fix, rather
/// than a bare parser message.
public struct ProjectManifestError: Error, Equatable, Sendable {
    /// The path of the file that failed to parse or validate.
    public let file: String
    /// The 1-indexed source line the failure was found at, when the YAML
    /// parser could locate one.
    public let line: Int?
    /// What to change to fix it, stated as an instruction.
    public let fix: String
}
