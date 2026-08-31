@testable import TalosProjectLibrary
import Testing

/// Verifies `allowlist.yaml` shape-parsing and round-trip serialization
/// against ``AllowlistManifest``. Taxonomy awareness — whether a name is
/// recognized, and whether its tier may be allowlisted — is a
/// `TalosSafeguards` concern, covered by `AllowlistStoreTests`; this suite
/// only proves the YAML shape this module owns.
@Suite("Allowlist manifest")
struct AllowlistManifestParserTests {
    @Test("A valid file parses into the typed model")
    func parsesAValidFile() throws {
        let yaml = """
        allowlist:
          - file.write
          - git.commit
        """

        let manifest = try AllowlistManifestParser.parse(contents: yaml, file: "allowlist.yaml")
        #expect(manifest.entries == ["file.write", "git.commit"])
    }

    @Test("An empty file parses into zero entries rather than an error")
    func emptyFileParsesIntoZeroEntries() throws {
        let manifest = try AllowlistManifestParser.parse(contents: "", file: "allowlist.yaml")
        #expect(manifest.entries.isEmpty)
    }

    @Test("A non-sequence allowlist value fails validation")
    func nonSequenceValueFailsValidation() {
        let yaml = "allowlist: file.write"

        #expect {
            try AllowlistManifestParser.parse(contents: yaml, file: "allowlist.yaml")
        } throws: { error in
            guard let error = error as? AllowlistManifestError else { return false }
            return error.file == "allowlist.yaml" && error.fix.contains("sequence")
        }
    }

    @Test("A non-scalar entry fails validation")
    func nonScalarEntryFailsValidation() {
        let yaml = """
        allowlist:
          - file.write
          - - nested
            - sequence
        """

        #expect {
            try AllowlistManifestParser.parse(contents: yaml, file: "allowlist.yaml")
        } throws: { error in
            guard let error = error as? AllowlistManifestError else { return false }
            return error.file == "allowlist.yaml" && error.line != nil
        }
    }

    @Test("An empty-string entry fails validation")
    func emptyStringEntryFailsValidation() {
        let yaml = """
        allowlist:
          - ""
        """

        #expect {
            try AllowlistManifestParser.parse(contents: yaml, file: "allowlist.yaml")
        } throws: { error in
            error is AllowlistManifestError
        }
    }

    @Test("Malformed YAML syntax names the file and the offending line")
    func malformedYAMLNamesFileAndLine() {
        let yaml = "allowlist: [unterminated\n"

        #expect {
            try AllowlistManifestParser.parse(contents: yaml, file: "allowlist.yaml")
        } throws: { error in
            guard let error = error as? AllowlistManifestError else { return false }
            return error.file == "allowlist.yaml" && !error.fix.isEmpty
        }
    }

    @Test("Serializing then parsing round-trips the same entries")
    func serializeThenParseRoundTrips() throws {
        let original = AllowlistManifest(entries: ["file.write", "git.commit", "board.item.move"])
        let text = AllowlistManifestParser.serialize(original)
        let roundTripped = try AllowlistManifestParser.parse(contents: text, file: "allowlist.yaml")

        #expect(roundTripped.entries == original.entries)
    }

    @Test("Serializing an empty manifest still parses back to zero entries")
    func serializeEmptyManifestRoundTrips() throws {
        let text = AllowlistManifestParser.serialize(AllowlistManifest())
        let roundTripped = try AllowlistManifestParser.parse(contents: text, file: "allowlist.yaml")

        #expect(roundTripped.entries.isEmpty)
    }
}
