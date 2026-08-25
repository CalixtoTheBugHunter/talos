@testable import TalosProjectLibrary
import Testing

/// Verifies `spec.yaml` parsing and validation against ``SpecManifest``.
@Suite("Spec manifest")
struct SpecManifestTests {
    // MARK: - Absence is a declared state

    @Test("A declared-absent Spec Drive parses successfully")
    func declaredAbsentSpecDriveParsesSuccessfully() throws {
        let yaml = """
        specDrive:
          status: absent
        """

        let manifest = try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        #expect(manifest.specDrive == .absent)
    }

    @Test("A missing specDrive key fails validation, distinct from a declared absence")
    func missingSpecDriveKeyFailsValidation() {
        #expect {
            try SpecManifestParser.parse(contents: "", file: "spec.yaml")
        } throws: { error in
            guard let error = error as? SpecManifestError else { return false }
            return error.file == "spec.yaml" && error.fix.contains("absent")
        }
    }

    /// An empty `locations` list under `status: present` is a broken
    /// present declaration, not the same thing as a declared absence — it
    /// must fail rather than silently being read as `.absent`.
    @Test("An empty locations list under status: present fails validation, distinct from absent")
    func emptyLocationsListFailsValidation() {
        let yaml = """
        specDrive:
          status: present
          locations: []
        """

        #expect {
            try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        } throws: { error in
            guard let error = error as? SpecManifestError else { return false }
            return error.file == "spec.yaml" && error.fix.contains("absent")
        }
    }

    @Test("status: absent declared together with locations fails validation as a contradiction")
    func absentWithLocationsFailsValidation() {
        let yaml = """
        specDrive:
          status: absent
          locations:
            - provider: github-wiki
              url: https://github.com/org/repo/wiki
              syncRule: read-only
        """

        #expect {
            try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        } throws: { error in
            guard let error = error as? SpecManifestError else { return false }
            return error.file == "spec.yaml" && error.fix.contains("locations")
        }
    }

    @Test("An unrecognized status value fails validation, listing the recognized ones")
    func unrecognizedStatusFailsValidation() {
        let yaml = """
        specDrive:
          status: unknown
        """

        #expect {
            try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        } throws: { error in
            guard let error = error as? SpecManifestError else { return false }
            return error.file == "spec.yaml" && error.fix.contains("absent") && error.fix.contains("present")
        }
    }

    // MARK: - Typed model for one or more locations and their sync rules

    @Test("A single GitHub Wiki location with a read-only sync rule parses into the typed model")
    func singleLocationParses() throws {
        let yaml = """
        specDrive:
          status: present
          locations:
            - provider: github-wiki
              url: https://github.com/CalixtoTheBugHunter/talos/wiki
              syncRule: read-only
        """

        let manifest = try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        guard case let .locations(locations) = manifest.specDrive else {
            Issue.record("Expected .locations, got \(manifest.specDrive)")
            return
        }
        #expect(locations.count == 1)
        let location = try #require(locations.first)
        #expect(location.provider == .githubWiki)
        #expect(location.url == "https://github.com/CalixtoTheBugHunter/talos/wiki")
        #expect(location.syncRule == .readOnly)
    }

    @Test("More than one location can be declared")
    func moreThanOneLocationCanBeDeclared() throws {
        let yaml = """
        specDrive:
          status: present
          locations:
            - provider: github-wiki
              url: https://github.com/org/repo-a/wiki
              syncRule: read-only
            - provider: github-wiki
              url: https://github.com/org/repo-b/wiki
              syncRule: talos-may-edit
        """

        let manifest = try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        guard case let .locations(locations) = manifest.specDrive else {
            Issue.record("Expected .locations, got \(manifest.specDrive)")
            return
        }
        #expect(locations.count == 2)
        #expect(locations.map(\.syncRule) == [.readOnly, .talosMayEdit])
    }

    @Test("A talos-may-edit sync rule parses into the typed model")
    func talosMayEditSyncRuleParses() throws {
        let yaml = """
        specDrive:
          status: present
          locations:
            - provider: github-wiki
              url: https://github.com/org/repo/wiki
              syncRule: talos-may-edit
        """

        let manifest = try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        guard case let .locations(locations) = manifest.specDrive else {
            Issue.record("Expected .locations, got \(manifest.specDrive)")
            return
        }
        #expect(locations.first?.syncRule == .talosMayEdit)
    }

    // MARK: - A declared location that cannot be resolved is a validation error naming it

    @Test("An unrecognized provider fails validation, listing the registered ones")
    func unrecognizedProviderFailsValidation() {
        let yaml = """
        specDrive:
          status: present
          locations:
            - provider: confluence
              url: https://example.atlassian.net/wiki
              syncRule: read-only
        """

        #expect {
            try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        } throws: { error in
            guard let error = error as? SpecManifestError else { return false }
            return error.file == "spec.yaml" && error.line != nil &&
                SpecDriveProviderKind.allCases.allSatisfy { error.fix.contains($0.rawValue) }
        }
    }

    @Test("A malformed url fails validation, naming it")
    func malformedURLFailsValidation() {
        let yaml = """
        specDrive:
          status: present
          locations:
            - provider: github-wiki
              url: "not a url"
              syncRule: read-only
        """

        #expect {
            try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        } throws: { error in
            guard let error = error as? SpecManifestError else { return false }
            return error.file == "spec.yaml" && error.line != nil && error.fix.contains("not a url")
        }
    }

    @Test("An empty url fails validation")
    func emptyURLFailsValidation() {
        let yaml = """
        specDrive:
          status: present
          locations:
            - provider: github-wiki
              url: ""
              syncRule: read-only
        """

        #expect {
            try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        } throws: { error in
            guard let error = error as? SpecManifestError else { return false }
            return error.file == "spec.yaml" && error.line != nil && error.fix.contains("url")
        }
    }

    @Test("An unrecognized sync rule fails validation")
    func unrecognizedSyncRuleFailsValidation() {
        let yaml = """
        specDrive:
          status: present
          locations:
            - provider: github-wiki
              url: https://github.com/org/repo/wiki
              syncRule: full-access
        """

        #expect {
            try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        } throws: { error in
            guard let error = error as? SpecManifestError else { return false }
            return error.file == "spec.yaml" &&
                error.fix.contains(SpecDriveSyncRule.readOnly.rawValue) &&
                error.fix.contains(SpecDriveSyncRule.talosMayEdit.rawValue)
        }
    }

    // MARK: - DRAFT items are representable

    /// `SpecItemStatus` carries no content and is not parsed from
    /// `spec.yaml` yet — it only needs to distinguish a draft item from a
    /// published one, since that distinction is the entire reason the type
    /// exists.
    @Test("SpecItemStatus distinguishes draft from published")
    func specItemStatusDistinguishesDraftFromPublished() {
        #expect(SpecItemStatus.draft != SpecItemStatus.published)
        #expect(Set([SpecItemStatus.draft, .published]).count == 2)
    }

    @Test("Malformed YAML syntax names the file and the offending line")
    func malformedYAMLNamesFileAndLine() {
        let yaml = "specDrive: [unterminated\n"

        #expect {
            try SpecManifestParser.parse(contents: yaml, file: "spec.yaml")
        } throws: { error in
            guard let error = error as? SpecManifestError else { return false }
            return error.file == "spec.yaml" && error.line != nil && !error.fix.isEmpty
        }
    }
}
