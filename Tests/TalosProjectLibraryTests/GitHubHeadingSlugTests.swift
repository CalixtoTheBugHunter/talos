@testable import TalosProjectLibrary
import Testing

/// Verifies the anchor slugs match the ones GitHub generates — the same anchors
/// every SPEC link on the wiki already targets.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
@Suite("GitHub heading slug")
struct GitHubHeadingSlugTests {
    @Test("Real SPEC headings slug to the anchors their links already use")
    func matchesRealAnchors() {
        #expect(GitHubHeadingSlug.slug(for: "How specs are retrieved") == "how-specs-are-retrieved")
        #expect(GitHubHeadingSlug.slug(for: "When a project has no Spec Drive") == "when-a-project-has-no-spec-drive")
        #expect(
            GitHubHeadingSlug.slug(for: "Missing context is labeled where the output is read")
                == "missing-context-is-labeled-where-the-output-is-read"
        )
    }

    @Test("Punctuation is dropped, case folded, spaces hyphenated")
    func dropsPunctuation() {
        #expect(GitHubHeadingSlug.slug(for: "Retention policy (DRAFT)") == "retention-policy-draft")
        #expect(GitHubHeadingSlug.slug(for: "RIPER-5: how an agent executes") == "riper-5-how-an-agent-executes")
    }

    @Test("Duplicate headings on a page get -1, -2 suffixes in order")
    func disambiguatesDuplicates() {
        var seen: [String: Int] = [:]
        #expect(GitHubHeadingSlug.uniqueSlug(for: "Rules", seen: &seen) == "rules")
        #expect(GitHubHeadingSlug.uniqueSlug(for: "Rules", seen: &seen) == "rules-1")
        #expect(GitHubHeadingSlug.uniqueSlug(for: "Rules", seen: &seen) == "rules-2")
    }
}
