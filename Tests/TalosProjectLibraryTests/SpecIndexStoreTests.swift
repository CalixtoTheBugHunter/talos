import Foundation
@testable import TalosProjectLibrary
import Testing

/// Verifies the derived Spec Drive index round-trips, replaces wholesale, lives
/// under `.talos/local/`, and never leaks one project's sections into another.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
@Suite("Spec index store")
struct SpecIndexStoreTests {
    private static func temporaryProjectRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func section(_ heading: String, draft: Bool = false, ordinal: Int = 0) -> SpecSection {
        SpecSection(
            pageTitle: "Guide",
            headingPath: ["Guide", heading],
            anchor: GitHubHeadingSlug.slug(for: heading),
            body: "Body of \(heading).",
            isDraft: draft,
            ordinal: ordinal
        )
    }

    @Test("The index database lives under .talos/local/")
    func databaseLivesUnderLocal() {
        let root = Self.temporaryProjectRoot()
        let url = SpecIndexSchema.databaseURL(projectRoot: root)
        #expect(url.path.hasSuffix(".talos/local/spec-index.sqlite"))
    }

    @Test("Stored sections read back with their fields and order intact")
    func roundTrips() async throws {
        let root = Self.temporaryProjectRoot()
        let store = try await SpecIndexStore.open(projectRoot: root)
        let project = ProjectIdentifier.generate()
        let written = [
            Self.section("Overview", ordinal: 0),
            Self.section("Roadmap", draft: true, ordinal: 1)
        ]

        try await store.replaceSections(written, project: project, locationURL: "https://example/wiki")
        let read = try await store.allSections(project: project)

        #expect(read == written)
    }

    @Test("Replacing a location's sections removes the previous ones")
    func replaceIsWholesale() async throws {
        let root = Self.temporaryProjectRoot()
        let store = try await SpecIndexStore.open(projectRoot: root)
        let project = ProjectIdentifier.generate()
        let location = "https://example/wiki"

        try await store.replaceSections([Self.section("Old")], project: project, locationURL: location)
        try await store.replaceSections([Self.section("New")], project: project, locationURL: location)
        let read = try await store.allSections(project: project)

        #expect(read.map(\.headingPath.last) == ["New"])
    }

    @Test("One project never reads another's sections")
    func projectsAreIsolated() async throws {
        let root = Self.temporaryProjectRoot()
        let store = try await SpecIndexStore.open(projectRoot: root)
        let mine = ProjectIdentifier.generate()
        let other = ProjectIdentifier.generate()

        try await store.replaceSections([Self.section("Mine")], project: mine, locationURL: "https://a/wiki")
        try await store.replaceSections([Self.section("Theirs")], project: other, locationURL: "https://b/wiki")

        #expect(try await store.allSections(project: mine).map(\.headingPath.last) == ["Mine"])
    }
}
