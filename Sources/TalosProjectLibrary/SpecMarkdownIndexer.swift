import Foundation

/// Turns one Spec Drive page's Markdown into the ``SpecSection``s the index
/// holds — page title, heading hierarchy, anchors, body text, and DRAFT status.
/// Structural only: it reads text the page already publishes and calls no
/// model.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
public enum SpecMarkdownIndexer {
    private static let maxHeadingLevel = 6

    /// Splits `markdown` into one section per ATX heading. Text before the first
    /// heading, or a page with none, becomes a single section under `pageTitle`.
    /// A section is DRAFT when its own heading or an ancestor's carries the
    /// `DRAFT` token, per
    /// [decision 84](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
    public static func sections(pageTitle: String, markdown: String) -> [SpecSection] {
        var builder = Builder(pageTitle: pageTitle)
        var inFence = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if isFenceDelimiter(line) {
                inFence.toggle()
                builder.appendBody(line)
            } else if !inFence, let heading = parseHeading(line) {
                builder.openHeading(level: heading.level, text: heading.text)
            } else {
                builder.appendBody(line)
            }
        }
        return builder.finish()
    }

    /// A DRAFT marker is the standalone uppercase token `DRAFT`, so `(DRAFT)` and
    /// `DRAFT:` match while a lower-case mention in prose does not.
    static func headingCarriesDraft(_ heading: String) -> Bool {
        heading.split { !$0.isLetter && !$0.isNumber }.contains("DRAFT")
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < maxHeadingLevel {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0, index < line.endIndex, line[index] == " " else { return nil }
        let text = line[index...]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }
}

/// One open heading on the parse stack — its level, text, and whether it (or an
/// ancestor) is DRAFT, so descendants inherit the marker.
private struct HeadingFrame {
    let level: Int
    let text: String
    let isDraft: Bool
}

/// The section currently accumulating body lines, held until the next heading
/// or the end of the page finalizes it.
private struct OpenSection {
    let path: [String]
    let anchor: String
    let isDraft: Bool
}

/// Accumulates sections as the parser walks the page, so the walk loop itself
/// stays small and the heading-stack bookkeeping lives in one place.
private struct Builder {
    let pageTitle: String
    private var sections: [SpecSection] = []
    private var stack: [HeadingFrame] = []
    private var seenSlugs: [String: Int] = [:]
    private var bodyLines: [String] = []
    private var openSection: OpenSection?
    private var ordinal = 0

    init(pageTitle: String) {
        self.pageTitle = pageTitle
    }

    mutating func appendBody(_ line: String) {
        bodyLines.append(line)
    }

    mutating func openHeading(level: Int, text: String) {
        flush()
        while let last = stack.last, last.level >= level {
            stack.removeLast()
        }
        let isDraft = SpecMarkdownIndexer.headingCarriesDraft(text) || stack.contains(where: \.isDraft)
        stack.append(HeadingFrame(level: level, text: text, isDraft: isDraft))
        openSection = OpenSection(
            path: stack.map(\.text),
            anchor: GitHubHeadingSlug.uniqueSlug(for: text, seen: &seenSlugs),
            isDraft: isDraft
        )
    }

    mutating func finish() -> [SpecSection] {
        flush()
        return sections
    }

    private mutating func flush() {
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        bodyLines = []
        if let open = openSection {
            append(path: open.path, anchor: open.anchor, body: body, isDraft: open.isDraft)
        } else if !body.isEmpty {
            // Text before any heading — kept under the page title rather than
            // lost; a page with no headings lands here too.
            append(
                path: [pageTitle],
                anchor: GitHubHeadingSlug.uniqueSlug(for: pageTitle, seen: &seenSlugs),
                body: body,
                isDraft: false
            )
        }
    }

    private mutating func append(path: [String], anchor: String, body: String, isDraft: Bool) {
        sections.append(SpecSection(
            pageTitle: pageTitle,
            headingPath: path,
            anchor: anchor,
            body: body,
            isDraft: isDraft,
            ordinal: ordinal
        ))
        ordinal += 1
    }
}
