import Foundation
@testable import TalosOrchestration
import TalosProjectLibrary
import Testing

/// The loop a refresh run closes, without a hand-built fixture anywhere in it:
/// Markdown the agent wrote into `.talos/local/` → the index Talos builds from
/// those files → the sections retrieval selects for a question.
///
/// Slice B's tests already ranked hand-made sections; what this verifies is that
/// nothing between the files and the answer is missing — the gap that made
/// criterion 4 unreachable while no code could build an index at all.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
@Suite("Spec Drive refresh round trip")
struct SpecDriveRefreshRoundTripTests {
    private static let wikiURL = "https://github.com/CalixtoTheBugHunter/talos/wiki"

    private static let fetchedPages = [
        "Deployment.md": """
        # Deployment

        ## Release cadence

        Talos ships on the first Tuesday of each month, signed and notarized.

        ## Teams (DRAFT)

        A shared deployment queue is planned, not current.
        """,
        "Home.md": """
        # Home

        Start with the vision page.
        """
    ]

    /// Writes `fetchedPages` where a refresh run would have left them, then
    /// builds the index from those files and reads it back.
    private static func indexedSections() async throws -> [SpecSection] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let request = GitHubWikiSpecDriveProvider().fetchRequest(
            for: SpecDriveLocation(provider: .githubWiki, url: wikiURL, syncRule: .readOnly),
            projectRoot: root
        )
        try FileManager.default.createDirectory(at: request.destination, withIntermediateDirectories: true)
        for (name, markdown) in fetchedPages {
            try markdown.write(
                to: request.destination.appendingPathComponent(name, isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
        }
        let store = try await SpecIndexStore.open(projectRoot: root)
        let project = ProjectIdentifier.generate()
        _ = try await SpecDriveIndexBuilder().rebuild(requests: [request], project: project, store: store)
        return try await store.allSections(project: project)
    }

    private static func retrieval(sections: [SpecSection]) -> SpecDriveRetrieval {
        SpecDriveRetrieval(
            specDrive: .locations([SpecDriveLocation(provider: .githubWiki, url: wikiURL, syncRule: .readOnly)]),
            sections: sections
        )
    }

    private static func intent(_ content: String) -> Intent {
        Intent(content: content, source: .userText, project: .generate(), requestingSubFunction: .assistant)
    }

    @Test("A question answerable only from the fetched wiki retrieves the section that answers it")
    func retrievesTheAnsweringSection() async throws {
        let fragment = try await Self.retrieval(sections: Self.indexedSections())
            .fetch(for: Self.intent("What is the release cadence?"))

        guard case let .available(rendered) = fragment else {
            Issue.record("Expected retrievable spec context, got \(fragment).")
            return
        }
        #expect(rendered.contains("first Tuesday of each month"))
        #expect(rendered.contains("#release-cadence"))
    }

    @Test("A DRAFT section retrieved from the fetched wiki is labeled planned rather than current")
    func labelsADraftSection() async throws {
        let fragment = try await Self.retrieval(sections: Self.indexedSections())
            .fetch(for: Self.intent("Is there a shared deployment queue for teams?"))

        guard case let .available(rendered) = fragment else {
            Issue.record("Expected retrievable spec context, got \(fragment).")
            return
        }
        #expect(rendered.contains("DRAFT: planned, not current"))
    }

    @Test("Before any refresh has run, retrieval says the index is empty rather than answering unmarked")
    func unindexedSpecDriveIsLabeled() {
        let fragment = Self.retrieval(sections: [])
            .fetch(for: Self.intent("What is the release cadence?"))

        #expect(fragment == .unavailable(reason: "Spec Drive content is not indexed yet."))
    }
}
