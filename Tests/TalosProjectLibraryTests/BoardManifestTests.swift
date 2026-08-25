@testable import TalosProjectLibrary
import Testing

/// Verifies `board.yaml` parsing and validation against ``BoardManifest``,
/// including the unmapped-column resolution path Automator will depend on.
@Suite("Board manifest")
struct BoardManifestTests {
    private static let jiraShapedYAML = """
    board:
      provider: jira
      columns:
        "To Do": ready
        "In Progress": in-progress
        "Code Review": in-review
        "Done": done
    """

    private static let githubProjectsShapedYAML = """
    board:
      provider: github-projects
      columns:
        Backlog: backlog
        Todo: ready
        "In Progress": in-progress
        Done: done
    """

    // MARK: - Typed model, both provider shapes

    @Test("A Jira-shaped file parses into the typed model")
    func parsesAJiraShapedFile() throws {
        let manifest = try BoardManifestParser.parse(contents: Self.jiraShapedYAML, file: "board.yaml")

        #expect(manifest.provider == .jira)
        #expect(manifest.columns.count == 4)
        #expect(manifest.state(forColumn: "To Do") == .mapped(.ready))
        #expect(manifest.state(forColumn: "Code Review") == .mapped(.inReview))
    }

    @Test("A GitHub-Projects-shaped file parses into the typed model")
    func parsesAGitHubProjectsShapedFile() throws {
        let manifest = try BoardManifestParser.parse(contents: Self.githubProjectsShapedYAML, file: "board.yaml")

        #expect(manifest.provider == .githubProjects)
        #expect(manifest.columns.count == 4)
        #expect(manifest.state(forColumn: "Backlog") == .mapped(.backlog))
    }

    // MARK: - Many-to-one mapping

    @Test("Several provider columns may share one internal state")
    func severalColumnsShareOneState() throws {
        let yaml = """
        board:
          provider: jira
          columns:
            "Doing": in-progress
            "Code Review": in-progress
        """

        let manifest = try BoardManifestParser.parse(contents: yaml, file: "board.yaml")
        #expect(manifest.state(forColumn: "Doing") == .mapped(.inProgress))
        #expect(manifest.state(forColumn: "Code Review") == .mapped(.inProgress))
    }

    // MARK: - Unmapped is declared, never inferred

    @Test("A column with no counterpart resolves to unmapped, never a default state")
    func unmappedColumnResolvesToUnmapped() throws {
        let manifest = try BoardManifestParser.parse(contents: Self.jiraShapedYAML, file: "board.yaml")
        #expect(manifest.state(forColumn: "Some Other Column") == .unmapped)
    }

    @Test("A provider with no columns declared resolves every column unmapped")
    func noColumnsDeclaredResolvesEveryColumnUnmapped() throws {
        let yaml = """
        board:
          provider: jira
        """

        let manifest = try BoardManifestParser.parse(contents: yaml, file: "board.yaml")
        #expect(manifest.columns.isEmpty)
        #expect(manifest.state(forColumn: "To Do") == .unmapped)
    }

    // MARK: - Provider registry

    @Test("An unrecognized provider fails validation, listing the registered ones")
    func unrecognizedProviderFailsValidation() {
        let yaml = """
        board:
          provider: trello
        """

        #expect {
            try BoardManifestParser.parse(contents: yaml, file: "board.yaml")
        } throws: { error in
            guard let error = error as? BoardManifestError else { return false }
            return error.file == "board.yaml" && error.line != nil &&
                BoardProviderKind.allCases.allSatisfy { error.fix.contains($0.rawValue) }
        }
    }

    @Test("A missing provider names the file, the line, and a fix")
    func missingProviderNamesFileLineAndFix() {
        let yaml = """
        board:
          columns:
            "To Do": ready
        """

        #expect {
            try BoardManifestParser.parse(contents: yaml, file: "board.yaml")
        } throws: { error in
            guard let error = error as? BoardManifestError else { return false }
            return error.file == "board.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }

    @Test("A missing board key names the file, the line, and a fix")
    func missingBoardKeyNamesFileLineAndFix() {
        #expect {
            try BoardManifestParser.parse(contents: "", file: "board.yaml")
        } throws: { error in
            guard let error = error as? BoardManifestError else { return false }
            return error.file == "board.yaml" && !error.fix.isEmpty
        }
    }

    // MARK: - Internal state registry

    @Test("An unrecognized internal state fails validation, listing the six canonical states")
    func unrecognizedStateFailsValidation() {
        let yaml = """
        board:
          provider: jira
          columns:
            "To Do": someday
        """

        #expect {
            try BoardManifestParser.parse(contents: yaml, file: "board.yaml")
        } throws: { error in
            guard let error = error as? BoardManifestError else { return false }
            return error.file == "board.yaml" && error.line != nil &&
                BoardState.allCases.allSatisfy { error.fix.contains($0.rawValue) }
        }
    }

    // MARK: - Malformed YAML

    @Test("Malformed YAML syntax names the file and the offending line")
    func malformedYAMLNamesFileAndLine() {
        let yaml = "board: [unterminated\n"

        #expect {
            try BoardManifestParser.parse(contents: yaml, file: "board.yaml")
        } throws: { error in
            guard let error = error as? BoardManifestError else { return false }
            return error.file == "board.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }
}
