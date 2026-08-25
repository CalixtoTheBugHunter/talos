@testable import TalosProjectLibrary
import Testing

/// Verifies `project.yaml` parsing and validation against ``ProjectManifest``.
@Suite("Project manifest")
struct ProjectManifestTests {
    private static let validYAML = """
    id: 11111111-1111-1111-1111-111111111111
    agents:
      - claude-code
    subFunctions:
      assistant: true
      automator: true
      advisor: false
      self-improver: false
    """

    @Test("A valid file parses into the typed model")
    func parsesAValidFile() throws {
        let manifest = try ProjectManifestParser.parse(contents: Self.validYAML, file: "project.yaml")

        #expect(manifest.id == ProjectIdentifier(rawValue: "11111111-1111-1111-1111-111111111111"))
        #expect(manifest.configuredAgents == ["claude-code"])
        #expect(manifest.subFunctions[.assistant] == true)
        #expect(manifest.subFunctions[.automator] == true)
    }

    @Test("Advisor and Self-improver parse without error, enabled or not")
    func advisorAndSelfImproverAreRecognizedButInert() throws {
        let manifest = try ProjectManifestParser.parse(contents: Self.validYAML, file: "project.yaml")

        #expect(manifest.subFunctions[.advisor] == false)
        #expect(manifest.subFunctions[.selfImprover] == false)
    }

    @Test("A generated identifier is never empty, and two generated ids differ")
    func generatedIdentifierIsFreshEachTime() {
        let first = ProjectIdentifier.generate()
        let second = ProjectIdentifier.generate()

        #expect(!first.rawValue.isEmpty)
        #expect(first != second)
    }

    @Test("An unrecognized top-level key survives parse, serialize, and reparse")
    func unrecognizedTopLevelKeySurvivesRewrite() throws {
        let yamlWithUnknownKey = Self.validYAML + "\nhubMembership: talos-hub-42\n"

        let parsed = try ProjectManifestParser.parse(contents: yamlWithUnknownKey, file: "project.yaml")
        #expect(parsed.unknownTopLevelKeys["hubMembership"] == .string("talos-hub-42"))

        let rewritten = try ProjectManifestParser.serialize(parsed)
        let reparsed = try ProjectManifestParser.parse(contents: rewritten, file: "project.yaml")

        #expect(reparsed.unknownTopLevelKeys["hubMembership"] == .string("talos-hub-42"))
    }

    /// A quoted string that reads as another YAML type unquoted (`"true"`,
    /// `"null"`, `"42"`) is the case a naive re-emit gets wrong: writing it
    /// back as a bare, untagged scalar lets the next parse resolve it as a
    /// bool, null, or int instead of the string a human wrote.
    @Test("An unrecognized key whose value reads as another YAML type stays a string on rewrite")
    func unrecognizedKeyThatLooksLikeAnotherTypeSurvivesRewriteAsAString() throws {
        let yamlWithAmbiguousValue = Self.validYAML + "\nweird: \"true\"\n"

        let parsed = try ProjectManifestParser.parse(contents: yamlWithAmbiguousValue, file: "project.yaml")
        #expect(parsed.unknownTopLevelKeys["weird"] == .string("true"))

        let rewritten = try ProjectManifestParser.serialize(parsed)
        let reparsed = try ProjectManifestParser.parse(contents: rewritten, file: "project.yaml")

        #expect(reparsed.unknownTopLevelKeys["weird"] == .string("true"))
    }

    @Test("Parse, serialize, and reparse yields an identical model")
    func roundTripYieldsAnIdenticalModel() throws {
        let parsed = try ProjectManifestParser.parse(contents: Self.validYAML, file: "project.yaml")
        let serialized = try ProjectManifestParser.serialize(parsed)
        let reparsed = try ProjectManifestParser.parse(contents: serialized, file: "project.yaml")

        #expect(parsed == reparsed)
    }

    // MARK: - Validation errors name the file, the line, and the fix

    @Test("A missing id names the file, the line, and a fix")
    func missingIDNamesFileLineAndFix() {
        let yaml = "agents: []\n"

        #expect {
            try ProjectManifestParser.parse(contents: yaml, file: "project.yaml")
        } throws: { error in
            guard let error = error as? ProjectManifestError else { return false }
            return error.file == "project.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }

    @Test("Malformed YAML syntax names the file and the offending line")
    func malformedYAMLNamesFileAndLine() {
        let yaml = "id: [unterminated\n"

        #expect {
            try ProjectManifestParser.parse(contents: yaml, file: "project.yaml")
        } throws: { error in
            guard let error = error as? ProjectManifestError else { return false }
            return error.file == "project.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }

    @Test("A non-sequence agents value names the file, the line, and a fix")
    func wrongTypedAgentsNamesFileLineAndFix() {
        let yaml = """
        id: 11111111-1111-1111-1111-111111111111
        agents: claude-code
        """

        #expect {
            try ProjectManifestParser.parse(contents: yaml, file: "project.yaml")
        } throws: { error in
            guard let error = error as? ProjectManifestError else { return false }
            return error.file == "project.yaml" && error.line == 2 && !error.fix.isEmpty
        }
    }

    @Test("An unrecognized sub-function name names the file, the line, and a fix")
    func unrecognizedSubFunctionNamesFileLineAndFix() {
        let yaml = """
        id: 11111111-1111-1111-1111-111111111111
        subFunctions:
          not-a-real-sub-function: true
        """

        #expect {
            try ProjectManifestParser.parse(contents: yaml, file: "project.yaml")
        } throws: { error in
            guard let error = error as? ProjectManifestError else { return false }
            return error.file == "project.yaml" && error.line == 3 && !error.fix.isEmpty
        }
    }
}
