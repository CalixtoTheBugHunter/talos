import Foundation
@testable import TalosProjectLibrary
import Testing

/// Verifies the reader turns the JSON a fetch run leaves on disk into
/// ``BoardItem`` values, and that a missing or malformed store reads as no
/// items — derived and rebuildable, so its absence costs a refresh, not data.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
@Suite("Board state reader")
struct BoardStateReaderTests {
    private static func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func write(_ contents: String, to root: URL) throws {
        let file = BoardStateLayout.itemsFile(projectRoot: root)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test("Reads the stored items into BoardItem values, keeping the provider's own column name")
    func readsStoredItems() throws {
        let root = Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.write(
            """
            [
              {"id": "1", "title": "Wire the board", "column": "In Progress"},
              {"id": "2", "title": "Ship it", "column": "Todo"}
            ]
            """,
            to: root
        )

        #expect(BoardStateReader().read(projectRoot: root) == [
            BoardItem(id: "1", title: "Wire the board", column: "In Progress"),
            BoardItem(id: "2", title: "Ship it", column: "Todo")
        ])
    }

    @Test("An item's optional url, updatedBy, and updatedAt decode when the read supplied them")
    func readsOptionalProvenanceAndURL() throws {
        let root = Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.write(
            """
            [
              {"id": "1", "title": "Ship it", "column": "Done", "updatedBy": "ada", \
            "updatedAt": "2026-09-21", "url": "https://example.com/item/1"}
            ]
            """,
            to: root
        )

        #expect(BoardStateReader().read(projectRoot: root) == [
            BoardItem(
                id: "1",
                title: "Ship it",
                column: "Done",
                updatedBy: "ada",
                updatedAt: "2026-09-21",
                url: "https://example.com/item/1"
            )
        ])
    }

    @Test("A missing store reads as no items — a deleted store costs a refresh, not data")
    func missingStoreReadsEmpty() {
        #expect(BoardStateReader().read(projectRoot: Self.root()).isEmpty)
    }

    @Test("A malformed store reads as no items rather than failing the session")
    func malformedStoreReadsEmpty() throws {
        let root = Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.write("{ not a board array", to: root)

        #expect(BoardStateReader().read(projectRoot: root).isEmpty)
    }
}
