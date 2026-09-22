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

    /// Whether the project declares any `repo`-kind connector — the declared
    /// system a git operation reaches when the command names a bare remote
    /// (`origin`) rather than an explicit URL. Talos does not run git to resolve
    /// the remote (only the adapter layer may spawn a process), so a project
    /// with no repo connector reaches an undeclared system and one with a repo
    /// connector is trusted to reach its own repo.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
    public func declaresRepo() -> Bool {
        connectors.contains { $0.kind == .repo }
    }

    /// Whether a `repo`-kind connector declares `url` as its target — the check
    /// for a git command that named an explicit URL. Matched on a normalized
    /// form so `https://github.com/org/repo.git` and `git@github.com:org/repo`
    /// resolve to the same declared target; a URL matching no declared target
    /// is undeclared, never inferred.
    public func declaresTarget(_ url: String) -> Bool {
        let normalized = Self.normalizedRepoTarget(url)
        return connectors.contains { $0.kind == .repo && Self.normalizedRepoTarget($0.target) == normalized }
    }

    /// Reduces a repo URL to `host/path` in lowercase, dropping the scheme, any
    /// `user@` prefix, an scp-style `:` after the host, and a trailing `.git`
    /// or `/`, so the two ways of writing the same GitHub repo compare equal.
    private static func normalizedRepoTarget(_ url: String) -> String {
        var value = url.lowercased()
        if let range = value.range(of: "://") {
            value = String(value[range.upperBound...])
        }
        if let atSign = value.firstIndex(of: "@") {
            value = String(value[value.index(after: atSign)...])
        }
        // scp-style `host:org/repo` — the first colon separates host and path.
        if let colon = value.firstIndex(of: ":"), !value[value.startIndex ..< colon].contains("/") {
            value.replaceSubrange(colon ... colon, with: "/")
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        let gitSuffix = ".git"
        if value.hasSuffix(gitSuffix) {
            value.removeLast(gitSuffix.count)
        }
        return value
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
