@testable import TalosProjectLibrary
import Testing

/// Verifies a Spec Drive page's Markdown becomes the sections the index holds —
/// heading hierarchy, anchors, body, and DRAFT status per decision 84.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
@Suite("Spec markdown indexer")
struct SpecMarkdownIndexerTests {
    private static let page = """
    # Project Library

    Intro text.

    ## Spec Drive

    The source of truth.

    ### How specs are retrieved

    Keyword and structural retrieval.

    ## Roadmap (DRAFT)

    Planned work.

    ### Teams

    Future teams feature.
    """

    private func section(_ sections: [SpecSection], heading: String) -> SpecSection? {
        sections.first { $0.headingPath.last == heading }
    }

    @Test("Each heading becomes a section carrying its full heading path and body")
    func buildsSectionsWithPaths() {
        let sections = SpecMarkdownIndexer.sections(pageTitle: "Project Library", markdown: Self.page)

        #expect(sections.count == 5)
        let retrieved = section(sections, heading: "How specs are retrieved")
        #expect(retrieved?.headingPath == ["Project Library", "Spec Drive", "How specs are retrieved"])
        #expect(retrieved?.anchor == "how-specs-are-retrieved")
        #expect(retrieved?.body == "Keyword and structural retrieval.")
    }

    @Test("A DRAFT heading marks its section and its subsections, not its siblings")
    func draftInheritsToSubsections() {
        let sections = SpecMarkdownIndexer.sections(pageTitle: "Project Library", markdown: Self.page)

        #expect(section(sections, heading: "Roadmap (DRAFT)")?.isDraft == true)
        #expect(section(sections, heading: "Teams")?.isDraft == true)
        #expect(section(sections, heading: "Spec Drive")?.isDraft == false)
        #expect(section(sections, heading: "How specs are retrieved")?.isDraft == false)
    }

    @Test("A heading-looking line inside a code fence is body text, not a section")
    func ignoresHeadingsInFences() {
        let markdown = """
        # Title

        Body.

        ```
        # not a heading
        ```
        """
        let sections = SpecMarkdownIndexer.sections(pageTitle: "Title", markdown: markdown)

        #expect(sections.count == 1)
        #expect(sections.first?.headingPath == ["Title"])
        #expect(sections.first?.body.contains("# not a heading") == true)
    }

    @Test("A page with no headings is one section under the page title")
    func pageWithNoHeadings() {
        let sections = SpecMarkdownIndexer.sections(pageTitle: "Notes", markdown: "Just some prose, no headings.")

        #expect(sections.count == 1)
        #expect(sections.first?.headingPath == ["Notes"])
        #expect(sections.first?.isDraft == false)
    }
}
