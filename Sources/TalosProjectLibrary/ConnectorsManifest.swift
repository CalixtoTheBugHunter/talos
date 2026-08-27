import Foundation

/// The four kinds of connection Project Library § Connectors names by
/// example: "GitHub repo, monitoring tools, deployment tools, testing
/// tools."
public enum ConnectorKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case repo
    case monitoring
    case deployment
    case testing
}

/// Whether a connector is reached via MCP or CLI — "Prefer MCP tools, then
/// CLI" is a preference stated to whoever authors `connectors.yaml`, not a
/// rule this model enforces on the value declared here.
public enum ConnectorAccessMethod: String, Equatable, Hashable, Sendable {
    case mcp
    case cli
}

/// One connector declared in `connectors.yaml`, keyed by `name` in the
/// file. `env` is the only place a connector may carry a credential, and
/// every value in it is either a ``SecretReference`` or an ordinary
/// literal — the same ``EnvValue`` `agents.yaml`'s MCP servers use.
public struct ConnectorDeclaration: Equatable, Sendable {
    public let name: String
    public let kind: ConnectorKind
    public let target: String
    public let reachedVia: ConnectorAccessMethod
    public let env: [String: EnvValue]

    public init(
        name: String,
        kind: ConnectorKind,
        target: String,
        reachedVia: ConnectorAccessMethod,
        env: [String: EnvValue] = [:]
    ) {
        self.name = name
        self.kind = kind
        self.target = target
        self.reachedVia = reachedVia
        self.env = env
    }
}

/// The parsed, validated contents of `.talos/connectors.yaml` — the allowlist
/// of systems that may be touched at all, and the declared-systems registry
/// the Safeguards gate reads on every action.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
public struct ConnectorsManifest: Equatable, Sendable {
    public let connectors: [ConnectorDeclaration]

    public init(connectors: [ConnectorDeclaration] = []) {
        self.connectors = connectors
    }

    /// Answers "is system `name` declared for this project?" — the query
    /// the gate depends on for `connector.undeclared` classification. A
    /// pure lookup against what was parsed: a name with no matching entry
    /// is reported `false`, never inferred or auto-added.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
    public func isDeclared(_ name: String) -> Bool {
        connectors.contains { $0.name == name }
    }
}

/// A validation failure that names the file, the line, and the fix — the
/// same shape ``AgentsManifestError`` and ``SpecManifestError`` use.
public struct ConnectorsManifestError: Error, Equatable, Sendable {
    /// The path of the file that failed to parse or validate.
    public let file: String
    /// The 1-indexed source line the failure was found at, when the YAML
    /// parser could locate one.
    public let line: Int?
    /// What to change to fix it, stated as an instruction.
    public let fix: String
}
