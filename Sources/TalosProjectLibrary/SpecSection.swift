/// One indexed section of a Spec Drive page: a heading, the text under it, and
/// the anchor a SPEC link targets. Derived from the page's own Markdown by
/// ``SpecMarkdownIndexer`` and held in the rebuildable
/// [`.talos/local/`](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved)
/// index, never committed.
public struct SpecSection: Equatable, Sendable {
    /// The page this section belongs to — the wiki page title.
    public let pageTitle: String
    /// The heading trail from the page's top-level heading down to this
    /// section's own heading, so retrieval can show where a section sits.
    public let headingPath: [String]
    /// The GitHub heading anchor for this section — the same slug every SPEC
    /// link on the wiki already targets. Empty for text before any heading.
    public let anchor: String
    /// The section's own text, excluding its subsections' bodies.
    public let body: String
    /// Whether this section is DRAFT — planned work rather than current, per
    /// [decision 84](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions):
    /// a `DRAFT` token in this heading or an ancestor's.
    public let isDraft: Bool
    /// Stable order within the page, so a rebuilt index reads back in the same
    /// order the page declares.
    public let ordinal: Int

    public init(
        pageTitle: String,
        headingPath: [String],
        anchor: String,
        body: String,
        isDraft: Bool,
        ordinal: Int
    ) {
        self.pageTitle = pageTitle
        self.headingPath = headingPath
        self.anchor = anchor
        self.body = body
        self.isDraft = isDraft
        self.ordinal = ordinal
    }
}
