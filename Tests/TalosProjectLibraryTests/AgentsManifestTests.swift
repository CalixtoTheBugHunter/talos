@testable import TalosProjectLibrary
import Testing

/// Verifies `agents.yaml` parsing and validation against this issue's
/// acceptance criteria:
/// https://github.com/CalixtoTheBugHunter/talos/issues/43
@Suite("Agents manifest")
struct AgentsManifestTests {
    private static let validYAML = """
    agents:
      claude-code:
        adapter: claude-code
        mcpServers:
          - name: github
            command: npx
            args: ["-y", "@modelcontextprotocol/server-github"]
            env:
              GITHUB_TOKEN: keychain:github-pat
              NODE_ENV: production
        allowedCLIs:
          - git
          - gh
    """

    // MARK: - Typed model

    /// > Typed model for declaring agents, their adapter, MCP servers, and
    /// > allowed CLIs
    @Test("A valid file parses into the typed model")
    func parsesAValidFile() throws {
        let manifest = try AgentsManifestParser.parse(contents: Self.validYAML, file: "agents.yaml")

        #expect(manifest.agents.count == 1)
        let agent = try #require(manifest.agents.first)
        #expect(agent.name == "claude-code")
        #expect(agent.adapter == .claudeCode)
        #expect(agent.allowedCLIs == ["git", "gh"])

        let server = try #require(agent.mcpServers.first)
        #expect(server.name == "github")
        #expect(server.command == "npx")
        #expect(server.args == ["-y", "@modelcontextprotocol/server-github"])
    }

    @Test("An empty file parses into zero agents rather than an error")
    func emptyFileParsesIntoZeroAgents() throws {
        let manifest = try AgentsManifestParser.parse(contents: "", file: "agents.yaml")
        #expect(manifest.agents.isEmpty)
    }

    // MARK: - Secret references, never secrets (AC2, AC3)

    /// > Secret fields accept only a Keychain reference, never a literal
    /// > value
    @Test("A keychain: reference parses as a secret, not a literal")
    func keychainReferenceParsesAsASecret() throws {
        let manifest = try AgentsManifestParser.parse(contents: Self.validYAML, file: "agents.yaml")
        let env = try #require(manifest.agents.first?.mcpServers.first?.env)

        #expect(env["GITHUB_TOKEN"] == .secret(SecretReference(keychainName: "github-pat")))
    }

    /// > Secret fields accept only a Keychain reference, never a literal
    /// > value
    @Test("An ordinary, non-secret literal is accepted")
    func ordinaryLiteralIsAccepted() throws {
        let manifest = try AgentsManifestParser.parse(contents: Self.validYAML, file: "agents.yaml")
        let env = try #require(manifest.agents.first?.mcpServers.first?.env)

        #expect(env["NODE_ENV"] == .literal("production"))
    }

    /// > Secret fields accept only a Keychain reference, never a literal
    /// > value
    ///
    /// The env key's own name marks it as a credential field, so a literal
    /// there is rejected regardless of what the literal looks like.
    @Test("A credential-named key with a literal value fails validation, however benign the value looks")
    func credentialNamedKeyWithLiteralValueFailsValidation() {
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
            mcpServers:
              - name: github
                command: npx
                env:
                  GITHUB_TOKEN: not-obviously-secret-shaped
        """

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.line != nil &&
                error.fix.contains("GITHUB_TOKEN") && !error.fix.contains("not-obviously-secret-shaped")
        }
    }

    /// > A literal-looking secret (long high-entropy string, `sk-`/`ghp_`
    /// > prefixes) is a validation error, not a warning, naming the
    /// > offending key
    ///
    /// > A test asserts a config containing a literal secret fails
    /// > validation
    ///
    /// The value looks like a known credential shape even though the key
    /// name ("CONFIG_VALUE") gives no hint. Assembled from non-contiguous
    /// parts, per decision 66, so no secret-shaped literal is committed
    /// whole — the same technique `Tests/TalosCoreTests/LogRedactionTests.swift`
    /// already uses.
    @Test("A literal value with a recognized secret prefix fails validation, naming the key and not the value")
    func literalWithRecognizedSecretPrefixFailsValidation() {
        let literalSecret = "sk-" + String(repeating: "A", count: 40)
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
            mcpServers:
              - name: github
                command: npx
                env:
                  CONFIG_VALUE: \(literalSecret)
        """

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.line != nil &&
                error.fix.contains("CONFIG_VALUE") && !error.fix.contains(literalSecret)
        }
    }

    /// > A literal-looking secret (long high-entropy string, ...) is a
    /// > validation error
    ///
    /// No recognized prefix and no credential-shaped key name — this is the
    /// generic high-entropy path. Assembled from short, non-contiguous
    /// parts so the finished value is never a committed literal.
    @Test("A long, high-entropy literal with no recognized prefix fails validation")
    func highEntropyLiteralWithNoRecognizedPrefixFailsValidation() {
        let parts = ["Qx7L", "mu2Z", "pT9v", "B4wK", "6eR1", "sN8d", "C3aF5"]
        let highEntropyLiteral = parts.joined()
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
            mcpServers:
              - name: github
                command: npx
                env:
                  CONFIG_VALUE: \(highEntropyLiteral)
        """

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.line != nil && error.fix.contains("CONFIG_VALUE")
        }
    }

    /// Regression: a UUID-shaped identifier under a non-credential key is
    /// exactly the false-positive case a blanket "long alphanumeric run"
    /// filter would catch, and `Tests/TalosCoreTests/LogRedactionTests.swift`
    /// already asserts `LogRedaction` leaves it alone — this asserts the
    /// entropy heuristic agrees.
    @Test("A UUID-shaped literal under a non-credential key is not flagged as a secret")
    func uuidShapedLiteralIsNotFlagged() throws {
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
            mcpServers:
              - name: github
                command: npx
                env:
                  CORRELATION_ID: 550e8400-e29b-41d4-a716-446655440000
        """

        let manifest = try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        let env = try #require(manifest.agents.first?.mcpServers.first?.env)
        #expect(env["CORRELATION_ID"] == .literal("550e8400-e29b-41d4-a716-446655440000"))
    }

    // MARK: - Multiple agents (AC5)

    /// > More than one agent can be declared per project
    @Test("More than one agent can be declared")
    func moreThanOneAgentCanBeDeclared() throws {
        let yaml = """
        agents:
          claude-code:
            adapter: claude-code
          codex:
            adapter: codex-cli
        """

        let manifest = try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        let names = Set(manifest.agents.map(\.name))
        #expect(names == ["claude-code", "codex"])
    }

    // MARK: - Adapter registry (AC6)

    /// > Validation rejects an adapter name with no registered adapter,
    /// > listing valid ones
    @Test("An unrecognized adapter name fails validation, listing the registered ones")
    func unrecognizedAdapterNameFailsValidationListingRegisteredOnes() {
        let yaml = """
        agents:
          claude-code:
            adapter: made-up-adapter
        """

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.line != nil &&
                AdapterKind.allCases.allSatisfy { error.fix.contains($0.rawValue) }
        }
    }

    @Test("A missing adapter names the file, the line, and a fix")
    func missingAdapterNamesFileLineAndFix() {
        let yaml = """
        agents:
          claude-code:
            allowedCLIs: [git]
        """

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }

    @Test("Malformed YAML syntax names the file and the offending line")
    func malformedYAMLNamesFileAndLine() {
        let yaml = "agents: [unterminated\n"

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }
}
