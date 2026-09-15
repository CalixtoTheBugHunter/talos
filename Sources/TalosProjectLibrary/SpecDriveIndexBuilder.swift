import Foundation

/// Builds the derived Spec Drive index from the Markdown a refresh run left on
/// disk. Reads files and calls no model. Nothing caps how many pages are
/// indexed — the guideline's token ceiling bounds what reaches a prompt, and
/// partial indexing would serve partial spec invisibly, per
/// [decision 87](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
public struct SpecDriveIndexBuilder: Sendable {
    public struct LocationResult: Equatable, Sendable {
        public let locationURL: String
        public let pageCount: Int
        public let sectionCount: Int
    }

    public init() {
        // Stateless.
    }

    /// Indexes every fetched location, replacing what the index held for each.
    /// A missing or empty directory indexes nothing and still replaces, so a
    /// page that disappeared upstream leaves the index rather than lingering.
    public func rebuild(
        requests: [SpecDriveFetchRequest],
        project: ProjectIdentifier,
        store: SpecIndexStore
    ) async throws -> [LocationResult] {
        var results: [LocationResult] = []
        for request in requests {
            let pages = pages(in: request.destination)
            let sections = pages.flatMap { page in
                SpecMarkdownIndexer.sections(pageTitle: page.title, markdown: page.markdown)
            }
            try await store.replaceSections(sections, project: project, locationURL: request.location.url)
            results.append(LocationResult(
                locationURL: request.location.url,
                pageCount: pages.count,
                sectionCount: sections.count
            ))
        }
        return results
    }

    private struct Page {
        let title: String
        let markdown: String
    }

    /// Every `.md` file directly in `directory`, sorted for a stable rebuild. A
    /// file unreadable as UTF-8 is skipped, not fatal: the index is derived, so
    /// one bad page is a thinner index, not lost data.
    private func pages(in directory: URL) -> [Page] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.lowercased().hasSuffix(Self.markdownExtension) }
            .sorted()
            .compactMap { name in
                let file = directory.appendingPathComponent(name, isDirectory: false)
                guard let markdown = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                return Page(title: Self.pageTitle(fileName: name), markdown: markdown)
            }
    }

    private static let markdownExtension = ".md"

    /// A GitHub Wiki page's file name *is* its title (`Project-Library.md` →
    /// `Project-Library`), kept as written rather than re-spaced.
    static func pageTitle(fileName: String) -> String {
        String(fileName.dropLast(markdownExtension.count))
    }
}
