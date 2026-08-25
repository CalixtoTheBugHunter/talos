@testable import TalosProjectLibrary
import Testing

/// Verifies `connectors.yaml` parsing and validation against
/// ``ConnectorsManifest``, including the undeclared-system query path the
/// Safeguards gate depends on.
@Suite("Connectors manifest")
struct ConnectorsManifestTests {
    private static let validYAML = """
    connectors:
      github-repo:
        kind: repo
        target: https://github.com/org/repo
        reachedVia: mcp
        env:
          GITHUB_TOKEN: keychain:github-pat
          NODE_ENV: production
      datadog:
        kind: monitoring
        target: https://app.datadoghq.com/org
        reachedVia: cli
      staging-deploy:
        kind: deployment
        target: staging-cluster
        reachedVia: cli
      xcuitest:
        kind: testing
        target: xcodebuild
        reachedVia: cli
    """

    // MARK: - Typed model

    @Test("A valid file parses into the typed model, covering all four kinds")
    func parsesAValidFile() throws {
        let manifest = try ConnectorsManifestParser.parse(contents: Self.validYAML, file: "connectors.yaml")

        #expect(manifest.connectors.count == 4)
        let kinds = Set(manifest.connectors.map(\.kind))
        #expect(kinds == [.repo, .monitoring, .deployment, .testing])

        let repo = try #require(manifest.connectors.first { $0.name == "github-repo" })
        #expect(repo.kind == .repo)
        #expect(repo.target == "https://github.com/org/repo")
        #expect(repo.reachedVia == .mcp)

        let monitoring = try #require(manifest.connectors.first { $0.name == "datadog" })
        #expect(monitoring.reachedVia == .cli)
    }

    @Test("An empty file parses into zero connectors rather than an error")
    func emptyFileParsesIntoZeroConnectors() throws {
        let manifest = try ConnectorsManifestParser.parse(contents: "", file: "connectors.yaml")
        #expect(manifest.connectors.isEmpty)
    }

    // MARK: - Secret references, never secrets — same rule as agents.yaml

    @Test("A keychain: reference parses as a secret, not a literal")
    func keychainReferenceParsesAsASecret() throws {
        let manifest = try ConnectorsManifestParser.parse(contents: Self.validYAML, file: "connectors.yaml")
        let env = try #require(manifest.connectors.first { $0.name == "github-repo" }?.env)

        #expect(env["GITHUB_TOKEN"] == .secret(SecretReference(keychainName: "github-pat")))
    }

    @Test("An ordinary, non-secret literal is accepted")
    func ordinaryLiteralIsAccepted() throws {
        let manifest = try ConnectorsManifestParser.parse(contents: Self.validYAML, file: "connectors.yaml")
        let env = try #require(manifest.connectors.first { $0.name == "github-repo" }?.env)

        #expect(env["NODE_ENV"] == .literal("production"))
    }

    @Test("A credential-named key with a literal value fails validation, however benign the value looks")
    func credentialNamedKeyWithLiteralValueFailsValidation() {
        let yaml = """
        connectors:
          github-repo:
            kind: repo
            target: https://github.com/org/repo
            reachedVia: mcp
            env:
              GITHUB_TOKEN: not-obviously-secret-shaped
        """

        #expect {
            try ConnectorsManifestParser.parse(contents: yaml, file: "connectors.yaml")
        } throws: { error in
            guard let error = error as? ConnectorsManifestError else { return false }
            return error.file == "connectors.yaml" && error.line != nil &&
                error.fix.contains("GITHUB_TOKEN") && !error.fix.contains("not-obviously-secret-shaped")
        }
    }

    /// The recognized-prefix and high-entropy heuristics themselves are
    /// exercised once, against `EnvValueParsing`, by
    /// `AgentsManifestTests` — this suite only proves connectors wire that
    /// shared rule up, via the credential-named-key and UUID-shaped cases
    /// above and below.
    @Test("A UUID-shaped literal under a non-credential key is not flagged as a secret")
    func uuidShapedLiteralIsNotFlagged() throws {
        let yaml = """
        connectors:
          github-repo:
            kind: repo
            target: https://github.com/org/repo
            reachedVia: mcp
            env:
              CORRELATION_ID: 550e8400-e29b-41d4-a716-446655440000
        """

        let manifest = try ConnectorsManifestParser.parse(contents: yaml, file: "connectors.yaml")
        let env = try #require(manifest.connectors.first?.env)
        #expect(env["CORRELATION_ID"] == .literal("550e8400-e29b-41d4-a716-446655440000"))
    }

    @Test("An empty Keychain reference fails validation")
    func emptyKeychainReferenceFailsValidation() {
        let yaml = """
        connectors:
          github-repo:
            kind: repo
            target: https://github.com/org/repo
            reachedVia: mcp
            env:
              GITHUB_TOKEN: "keychain:"
        """

        #expect {
            try ConnectorsManifestParser.parse(contents: yaml, file: "connectors.yaml")
        } throws: { error in
            guard let error = error as? ConnectorsManifestError else { return false }
            return error.file == "connectors.yaml" && error.fix.contains("empty Keychain reference")
        }
    }

    // MARK: - Kind, target, and access-method registries

    @Test("An unrecognized kind fails validation, listing the registered ones")
    func unrecognizedKindFailsValidation() {
        let yaml = """
        connectors:
          github-repo:
            kind: chat
            target: https://github.com/org/repo
            reachedVia: mcp
        """

        #expect {
            try ConnectorsManifestParser.parse(contents: yaml, file: "connectors.yaml")
        } throws: { error in
            guard let error = error as? ConnectorsManifestError else { return false }
            return error.file == "connectors.yaml" && error.line != nil &&
                ConnectorKind.allCases.allSatisfy { error.fix.contains($0.rawValue) }
        }
    }

    @Test("A missing target names the file, the line, and a fix")
    func missingTargetNamesFileLineAndFix() {
        let yaml = """
        connectors:
          github-repo:
            kind: repo
            reachedVia: mcp
        """

        #expect {
            try ConnectorsManifestParser.parse(contents: yaml, file: "connectors.yaml")
        } throws: { error in
            guard let error = error as? ConnectorsManifestError else { return false }
            return error.file == "connectors.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }

    @Test("An empty target fails validation")
    func emptyTargetFailsValidation() {
        let yaml = """
        connectors:
          github-repo:
            kind: repo
            target: ""
            reachedVia: mcp
        """

        #expect {
            try ConnectorsManifestParser.parse(contents: yaml, file: "connectors.yaml")
        } throws: { error in
            guard let error = error as? ConnectorsManifestError else { return false }
            return error.file == "connectors.yaml" && error.fix.contains("target")
        }
    }

    @Test("An unrecognized reachedVia fails validation, listing mcp and cli")
    func unrecognizedReachedViaFailsValidation() {
        let yaml = """
        connectors:
          github-repo:
            kind: repo
            target: https://github.com/org/repo
            reachedVia: carrier-pigeon
        """

        #expect {
            try ConnectorsManifestParser.parse(contents: yaml, file: "connectors.yaml")
        } throws: { error in
            guard let error = error as? ConnectorsManifestError else { return false }
            return error.file == "connectors.yaml" &&
                error.fix.contains(ConnectorAccessMethod.mcp.rawValue) &&
                error.fix.contains(ConnectorAccessMethod.cli.rawValue)
        }
    }

    @Test("A missing reachedVia names the file, the line, and a fix")
    func missingReachedViaNamesFileLineAndFix() {
        let yaml = """
        connectors:
          github-repo:
            kind: repo
            target: https://github.com/org/repo
        """

        #expect {
            try ConnectorsManifestParser.parse(contents: yaml, file: "connectors.yaml")
        } throws: { error in
            guard let error = error as? ConnectorsManifestError else { return false }
            return error.file == "connectors.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }

    // MARK: - Multiple connectors

    @Test("More than one connector can be declared")
    func moreThanOneConnectorCanBeDeclared() throws {
        let manifest = try ConnectorsManifestParser.parse(contents: Self.validYAML, file: "connectors.yaml")
        let names = Set(manifest.connectors.map(\.name))
        #expect(names == ["github-repo", "datadog", "staging-deploy", "xcuitest"])
    }

    // MARK: - The declared-systems registry: the undeclared-query path the gate depends on

    @Test("isDeclared answers true for a declared system's name")
    func isDeclaredAnswersTrueForADeclaredSystem() throws {
        let manifest = try ConnectorsManifestParser.parse(contents: Self.validYAML, file: "connectors.yaml")
        #expect(manifest.isDeclared("github-repo"))
    }

    @Test("isDeclared answers false for an undeclared system, never inferring it")
    func isDeclaredAnswersFalseForAnUndeclaredSystem() throws {
        let manifest = try ConnectorsManifestParser.parse(contents: Self.validYAML, file: "connectors.yaml")
        #expect(!manifest.isDeclared("some-other-system"))
    }

    @Test("isDeclared on an empty manifest reports every name undeclared")
    func isDeclaredOnAnEmptyManifestReportsEveryNameUndeclared() throws {
        let manifest = try ConnectorsManifestParser.parse(contents: "", file: "connectors.yaml")
        #expect(!manifest.isDeclared("github-repo"))
    }

    // MARK: - Malformed YAML

    @Test("Malformed YAML syntax names the file and the offending line")
    func malformedYAMLNamesFileAndLine() {
        let yaml = "connectors: [unterminated\n"

        #expect {
            try ConnectorsManifestParser.parse(contents: yaml, file: "connectors.yaml")
        } throws: { error in
            guard let error = error as? ConnectorsManifestError else { return false }
            return error.file == "connectors.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }
}
