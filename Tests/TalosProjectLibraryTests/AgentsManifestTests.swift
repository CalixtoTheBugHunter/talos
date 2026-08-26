@testable import TalosProjectLibrary
import Testing

/// Verifies `agents.yaml` parsing and validation against ``AgentsManifest``.
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

    @Test("A valid file parses into the typed model")
    func parsesAValidFile() throws {
        let manifest = try AgentsManifestParser.parse(contents: Self.validYAML, file: "agents.yaml")

        #expect(manifest.agents.count == 1)
        let agent = try #require(manifest.agents.first)
        #expect(agent.name == "claude-code")
        #expect(agent.adapter == "claude-code")
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

    // MARK: - Secret references, never secrets

    @Test("A keychain: reference parses as a secret, not a literal")
    func keychainReferenceParsesAsASecret() throws {
        let manifest = try AgentsManifestParser.parse(contents: Self.validYAML, file: "agents.yaml")
        let env = try #require(manifest.agents.first?.mcpServers.first?.env)

        #expect(env["GITHUB_TOKEN"] == .secret(SecretReference(keychainName: "github-pat")))
    }

    @Test("An ordinary, non-secret literal is accepted")
    func ordinaryLiteralIsAccepted() throws {
        let manifest = try AgentsManifestParser.parse(contents: Self.validYAML, file: "agents.yaml")
        let env = try #require(manifest.agents.first?.mcpServers.first?.env)

        #expect(env["NODE_ENV"] == .literal("production"))
    }

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

    /// The value looks like a known credential shape even though the key
    /// name ("CONFIG_VALUE") gives no hint. Assembled from non-contiguous
    /// parts so no secret-shaped literal is committed whole — the same
    /// technique `Tests/TalosCoreTests/LogRedactionTests.swift` uses.
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

    // MARK: - Multiple agents

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

    // MARK: - The adapter name is carried, not judged

    /// The parser holds no list of adapter names. `AgentAdapterRegistry` is the
    /// one validator, so a name is carried through to resolution and fails
    /// there against what is actually registered — never here, against a
    /// second list that can disagree with it.
    /// § The contract you implement —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-contract-you-implement
    ///
    /// > **Adding an agent means writing one adapter, never touching Talos core.**
    ///
    /// The regression this asserts: reintroducing a known-names check here
    /// would reject a registered third-party adapter before the registry is
    /// ever asked, which is the core edit the SPEC line above forbids.
    @Test("An adapter name the parser has never heard of is carried through verbatim")
    func anUnknownAdapterNameIsCarriedThroughVerbatim() throws {
        let yaml = """
        agents:
          some-agent:
            adapter: third-party-cli
        """

        let manifest = try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")

        #expect(manifest.agents.first?.adapter == "third-party-cli")
    }

    /// Exact, so a near-miss reaches the registry as written and fails there
    /// naming the value the user typed rather than a normalized one.
    @Test("The adapter name is not lowercased, trimmed, or otherwise normalized")
    func theAdapterNameIsNotNormalized() throws {
        let yaml = """
        agents:
          some-agent:
            adapter: Third_Party-CLI
        """

        let manifest = try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")

        #expect(manifest.agents.first?.adapter == "Third_Party-CLI")
    }

    /// An empty value is a missing one: `adapter: ""` would otherwise reach the
    /// registry as a name nobody could have registered.
    @Test("An empty adapter name fails as a missing one")
    func anEmptyAdapterNameFailsAsMissing() {
        let yaml = """
        agents:
          some-agent:
            adapter: ""
        """

        #expect {
            try AgentsManifestParser.parse(contents: yaml, file: "agents.yaml")
        } throws: { error in
            guard let error = error as? AgentsManifestError else { return false }
            return error.file == "agents.yaml" && error.fix.contains("adapter")
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
