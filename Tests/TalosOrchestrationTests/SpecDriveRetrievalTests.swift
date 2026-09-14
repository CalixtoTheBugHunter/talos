@testable import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Verifies lexical Spec Drive retrieval: selective, DRAFT-labeled, and honest
/// about a thin or empty result — the input DoD criterion 4 measures Assistant
/// against.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
@Suite("Spec Drive retrieval")
struct SpecDriveRetrievalTests {
    private static func intent(_ content: String) -> Intent {
        Intent(content: content, source: .userText, project: .generate(), requestingSubFunction: .assistant)
    }

    private static func section(_ heading: String, _ body: String, draft: Bool = false, ordinal: Int) -> SpecSection {
        SpecSection(
            pageTitle: "Guide",
            headingPath: ["Guide", heading],
            anchor: GitHubHeadingSlug.slug(for: heading),
            body: body,
            isDraft: draft,
            ordinal: ordinal
        )
    }

    private static let present = SpecDrive.locations([
        SpecDriveLocation(provider: .githubWiki, url: "https://example/wiki", syncRule: .readOnly)
    ])

    private static let sections = [
        section("Spec Drive retrieval", "Keyword and structural retrieval over an index.", ordinal: 0),
        section("Board columns", "Map provider columns to internal states.", ordinal: 1),
        section("Teams roadmap", "Planned teams collaboration feature.", draft: true, ordinal: 2)
    ]

    @Test("A declared-absent Spec Drive is unavailable, not an error")
    func absentIsUnavailable() {
        let fragment = SpecDriveRetrieval(specDrive: .absent).fetch(for: Self.intent("anything"))
        #expect(fragment == .unavailable(reason: "This project declares no Spec Drive."))
    }

    @Test("A present Spec Drive with an empty index reports it is not indexed yet")
    func emptyIndexIsUnavailable() {
        let fragment = SpecDriveRetrieval(specDrive: Self.present, sections: []).fetch(for: Self.intent("spec"))
        #expect(fragment == .unavailable(reason: "Spec Drive content is not indexed yet."))
    }

    @Test("Retrieval selects the relevant section and leaves out the unrelated one")
    func selectsRelevantSections() {
        let retrieval = SpecDriveRetrieval(specDrive: Self.present, sections: Self.sections)
        let fragment = retrieval.fetch(for: Self.intent("What does the spec drive retrieval do?"))

        guard case let .available(text) = fragment else {
            Issue.record("expected an available fragment, got \(fragment)")
            return
        }
        #expect(text.contains("Spec Drive retrieval"))
        #expect(!text.contains("Board columns"))
    }

    @Test("A matching DRAFT section is labeled planned rather than current")
    func draftSectionIsLabeled() {
        let retrieval = SpecDriveRetrieval(specDrive: Self.present, sections: Self.sections)
        let fragment = retrieval.fetch(for: Self.intent("teams roadmap"))

        guard case let .available(text) = fragment else {
            Issue.record("expected an available fragment, got \(fragment)")
            return
        }
        #expect(text.contains("Teams roadmap"))
        #expect(text.contains("DRAFT: planned, not current"))
    }

    @Test("A question that matches no section is a labeled thin result, not a guess")
    func noMatchIsUnavailable() {
        let retrieval = SpecDriveRetrieval(specDrive: Self.present, sections: Self.sections)
        let fragment = retrieval.fetch(for: Self.intent("xylophone"))
        #expect(fragment == .unavailable(reason: "No indexed spec section matched the question."))
    }

    @Test("A tiny token budget keeps retrieval selective")
    func budgetLimitsSelection() {
        let many = (0 ..< 10).map {
            Self.section("Retrieval note \($0)", "Spec retrieval detail number \($0).", ordinal: $0)
        }
        let selected = SpecLexicalRanking.select(sections: many, query: "spec retrieval", tokenBudget: 5)
        #expect(selected.count < many.count)
        #expect(!selected.isEmpty)
    }
}
