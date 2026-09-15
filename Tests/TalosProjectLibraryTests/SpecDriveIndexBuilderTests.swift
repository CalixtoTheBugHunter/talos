import Foundation
@testable import TalosProjectLibrary
import Testing

/// Verifies the index is built from the Markdown a refresh run left on disk —
/// "content is indexed locally so retrieval does not re-fetch per turn" — with no
/// cap on how much is indexed, per
/// [decision 87](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
@Suite("Spec Drive index builder")
struct SpecDriveIndexBuilderTests {
    private static let wikiURL = "https://github.com/CalixtoTheBugHunter/talos/wiki"

    /// A project root with one fetched location on disk, holding `pages` as
    /// `name.md` files where the agent would have written them.
    private static func fetchedProject(pages: [String: String]) throws -> (root: URL, request: SpecDriveFetchRequest) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let request = GitHubWikiSpecDriveProvider().fetchRequest(
            for: SpecDriveLocation(provider: .githubWiki, url: wikiURL, syncRule: .readOnly),
            projectRoot: root
        )
        try FileManager.default.createDirectory(at: request.destination, withIntermediateDirectories: true)
        for (name, markdown) in pages {
            try markdown.write(
                to: request.destination.appendingPathComponent(name, isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
        }
        return (root, request)
    }

    private static func rebuild(
        root: URL,
        requests: [SpecDriveFetchRequest]
    ) async throws -> (results: [SpecDriveIndexBuilder.LocationResult], sections: [SpecSection]) {
        let store = try await SpecIndexStore.open(projectRoot: root)
        let project = ProjectIdentifier.generate()
        let results = try await SpecDriveIndexBuilder().rebuild(requests: requests, project: project, store: store)
        return try await (results, store.allSections(project: project))
    }

    @Test("A fetched page becomes indexed sections carrying its title, heading path, and anchor")
    func indexesAFetchedPage() async throws {
        let fetched = try Self.fetchedProject(pages: [
            "Project-Library.md": """
            # Project Library

            Intro.

            ## Where it lives

            Under `.talos/`.
            """
        ])
        let built = try await Self.rebuild(root: fetched.root, requests: [fetched.request])

        #expect(built.results == [SpecDriveIndexBuilder.LocationResult(
            locationURL: Self.wikiURL,
            pageCount: 1,
            sectionCount: 2
        )])
        #expect(built.sections.map(\.pageTitle) == ["Project-Library", "Project-Library"])
        #expect(built.sections.map(\.headingPath) == [
            ["Project Library"],
            ["Project Library", "Where it lives"]
        ])
        #expect(built.sections.map(\.anchor) == ["project-library", "where-it-lives"])
    }

    @Test("A DRAFT heading marks its section and its subsections as planned rather than current")
    func draftIsCarriedThrough() async throws {
        let fetched = try Self.fetchedProject(pages: [
            "Roadmap.md": """
            ## Shipped

            Today's rule.

            ## Teams (DRAFT)

            ### Sharing

            Planned.
            """
        ])
        let built = try await Self.rebuild(root: fetched.root, requests: [fetched.request])

        #expect(built.sections.map(\.isDraft) == [false, true, true])
    }

    @Test("Only Markdown files are indexed, so a clone's own files never enter the index")
    func ignoresNonMarkdownFiles() async throws {
        let fetched = try Self.fetchedProject(pages: [
            "Home.md": "# Home\n\nStart here.",
            "notes.txt": "# Not a wiki page\n\nIgnored.",
            "config.yaml": "key: value"
        ])
        let built = try await Self.rebuild(root: fetched.root, requests: [fetched.request])

        #expect(built.results.first?.pageCount == 1)
        #expect(built.sections.map(\.pageTitle) == ["Home"])
    }

    @Test("A rebuild replaces wholesale, so a page deleted upstream leaves the index")
    func rebuildDropsPagesThatDisappeared() async throws {
        let fetched = try Self.fetchedProject(pages: [
            "Home.md": "# Home\n\nStart here.",
            "Gone.md": "# Gone\n\nRemoved upstream."
        ])
        let store = try await SpecIndexStore.open(projectRoot: fetched.root)
        let project = ProjectIdentifier.generate()
        let builder = SpecDriveIndexBuilder()
        _ = try await builder.rebuild(requests: [fetched.request], project: project, store: store)

        try FileManager.default.removeItem(at: fetched.request.destination.appendingPathComponent("Gone.md"))
        _ = try await builder.rebuild(requests: [fetched.request], project: project, store: store)

        #expect(try await store.allSections(project: project).map(\.pageTitle) == ["Home"])
    }

    @Test("A location the agent never wrote indexes nothing rather than failing the rebuild")
    func missingDestinationIndexesNothing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let request = GitHubWikiSpecDriveProvider().fetchRequest(
            for: SpecDriveLocation(provider: .githubWiki, url: Self.wikiURL, syncRule: .readOnly),
            projectRoot: root
        )
        let built = try await Self.rebuild(root: root, requests: [request])

        #expect(built.results.first?.pageCount == 0)
        #expect(built.sections.isEmpty)
    }

    @Test("Every fetched page is indexed — no page or byte cap bounds the builder")
    func indexesEveryPageWithNoCap() async throws {
        let pageCount = 120
        let pages = Dictionary(uniqueKeysWithValues: (0 ..< pageCount).map { index in
            ("Page-\(index).md", "# Page \(index)\n\nBody \(index).")
        })
        let fetched = try Self.fetchedProject(pages: pages)
        let built = try await Self.rebuild(root: fetched.root, requests: [fetched.request])

        #expect(built.results.first?.pageCount == pageCount)
        #expect(built.sections.count == pageCount)
    }

    @Test("A wiki page's file name is the page title every SPEC link already uses")
    func pageTitleIsTheFileName() {
        #expect(SpecDriveIndexBuilder.pageTitle(fileName: "Project-Library.md") == "Project-Library")
    }
}
