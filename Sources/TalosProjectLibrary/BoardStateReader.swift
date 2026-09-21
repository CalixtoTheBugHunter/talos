import Foundation

/// Reads the board items a fetch run left on disk into ``BoardItem`` values.
/// Reads a file and calls no model and no network. A missing, empty, or
/// malformed file reads as no items: the store is derived and rebuildable, so
/// its absence costs a refresh, not data, and the caller labels the absence
/// where the output is read.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
public struct BoardStateReader: Sendable {
    public init() {
        // Stateless.
    }

    /// The items stored under `.talos/local/board`, or `[]` when none were
    /// stored or the file cannot be decoded.
    public func read(projectRoot: URL) -> [BoardItem] {
        let file = BoardStateLayout.itemsFile(projectRoot: projectRoot)
        guard let data = try? Data(contentsOf: file),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else {
            return []
        }
        return rows.map {
            BoardItem(id: $0.id, title: $0.title, column: $0.column, updatedBy: $0.updatedBy, updatedAt: $0.updatedAt)
        }
    }

    /// The canonical on-disk shape the fetch instruction fixes, decoded into
    /// ``BoardItem`` so no provider-specific field is modeled in Talos.
    /// `updatedBy`/`updatedAt` are optional: a provider that exposes neither
    /// still reads cleanly.
    private struct Row: Decodable {
        let id: String
        let title: String
        let column: String
        let updatedBy: String?
        let updatedAt: String?
    }
}
