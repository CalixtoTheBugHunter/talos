import Foundation
@testable import TalosPersistence
import Testing

/// `Database/execute(_:)` is "trusted, schema-controlled text only, never
/// user-supplied input" — these are the bound-parameter `run`/`query` that
/// dynamic, potentially untrusted values (an agent-derived failure reason,
/// a project identifier) go through instead.
@Suite("Database parameter binding")
struct DatabaseBindingTests {
    private static func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("test.sqlite", isDirectory: false)
    }

    private static let schema = Migration(
        version: 1,
        name: "create a bindings test table",
        sql: """
        CREATE TABLE items (
            id INTEGER PRIMARY KEY,
            project_id TEXT NOT NULL,
            label TEXT,
            count INTEGER,
            ratio REAL
        );
        """
    )

    @Test("Bound text, integer, double, and null values round-trip exactly")
    func boundValuesRoundTrip() async throws {
        let database = try await Database(url: Self.temporaryDatabaseURL(), migrations: [Self.schema])

        try await database.run(
            "INSERT INTO items (id, project_id, label, count, ratio) VALUES (?, ?, ?, ?, ?);",
            bindings: [.int(1), .text("p1"), .text("hello"), .int(3), .double(0.5)]
        )
        try await database.run(
            "INSERT INTO items (id, project_id, label, count, ratio) VALUES (?, ?, ?, ?, ?);",
            bindings: [.int(2), .text("p1"), .null, .null, .null]
        )

        let rows = try await database.query(
            "SELECT id, label, count, ratio FROM items ORDER BY id;"
        )

        #expect(rows == [
            [.int(1), .text("hello"), .int(3), .double(0.5)],
            [.int(2), .null, .null, .null]
        ])
    }

    /// A value shaped like a SQL-injection attempt is bound as data, not
    /// concatenated as SQL — the table this test would otherwise drop is
    /// still there afterward, with the string stored literally.
    @Test("A value shaped like a SQL injection is stored as data, not executed")
    func sqlInjectionShapedValueIsStoredAsData() async throws {
        let database = try await Database(url: Self.temporaryDatabaseURL(), migrations: [Self.schema])
        let malicious = "'); DROP TABLE items; --"

        try await database.run(
            "INSERT INTO items (id, project_id, label) VALUES (?, ?, ?);",
            bindings: [.int(1), .text("p1"), .text(malicious)]
        )

        #expect(try await database.tableNames().contains("items"))
        let rows = try await database.query("SELECT label FROM items WHERE id = ?;", bindings: [.int(1)])
        #expect(rows == [[.text(malicious)]])
    }

    @Test("A query scoped by a bound project id returns only that project's rows")
    func queryIsScopedByBoundProjectID() async throws {
        let database = try await Database(url: Self.temporaryDatabaseURL(), migrations: [Self.schema])
        try await database.run(
            "INSERT INTO items (id, project_id, label) VALUES (?, ?, ?);",
            bindings: [.int(1), .text("p1"), .text("a")]
        )
        try await database.run(
            "INSERT INTO items (id, project_id, label) VALUES (?, ?, ?);",
            bindings: [.int(2), .text("p2"), .text("b")]
        )

        let rows = try await database.query(
            "SELECT label FROM items WHERE project_id = ?;",
            bindings: [.text("p2")]
        )

        #expect(rows == [[.text("b")]])
    }
}
