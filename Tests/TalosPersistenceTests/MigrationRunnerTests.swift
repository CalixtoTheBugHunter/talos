import Foundation
@testable import TalosPersistence
import Testing

/// Verifies the migration runner and the invariants it enforces.
@Suite("Migration runner")
struct MigrationRunnerTests {
    /// A fresh temporary directory per test, so parallel tests never share a
    /// database file.
    private static func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("test.sqlite", isDirectory: false)
    }

    private static let exampleSchema = Migration(
        version: 1,
        name: "create example tables",
        sql: """
        CREATE TABLE exampleSessions (
            id INTEGER PRIMARY KEY,
            project_id TEXT NOT NULL
        );
        CREATE TABLE exampleTokenRecords (
            id INTEGER PRIMARY KEY,
            project_id TEXT NOT NULL,
            session_id INTEGER NOT NULL REFERENCES exampleSessions(id) ON DELETE CASCADE
        );
        """
    )

    /// > A forward-only migration runner applies versioned migrations at
    /// > launch and is covered by tests, including a migration-from-empty
    /// > test.
    @Test("A migration runs against a brand-new, empty database")
    func migrationFromEmpty() async throws {
        let url = Self.temporaryDatabaseURL()
        let database = try await Database(url: url, migrations: [Self.exampleSchema])

        #expect(try await database.userVersion() == 1)
        #expect(try await Set(database.tableNames()) == ["exampleSessions", "exampleTokenRecords"])
    }

    /// Forward-only: reopening at the same version does not reapply a
    /// migration whose SQL would fail the second time (`CREATE TABLE` with no
    /// `IF NOT EXISTS`), proving it only runs once.
    @Test("A migration already applied is never reapplied")
    func migrationsAreForwardOnly() async throws {
        let url = Self.temporaryDatabaseURL()
        _ = try await Database(url: url, migrations: [Self.exampleSchema])

        // Reopening with the same migration list must not re-run version 1's
        // CREATE TABLE, which would throw on a duplicate table name.
        let reopened = try await Database(url: url, migrations: [Self.exampleSchema])
        #expect(try await reopened.userVersion() == 1)
    }

    /// A later launch with a newer migration list applies only what is new.
    @Test("Only migrations newer than the current version are applied")
    func onlyNewerMigrationsApply() async throws {
        let url = Self.temporaryDatabaseURL()
        _ = try await Database(url: url, migrations: [Self.exampleSchema])

        let addColumn = Migration(
            version: 2,
            name: "add a column",
            sql: "ALTER TABLE exampleSessions ADD COLUMN note TEXT;"
        )
        let reopened = try await Database(url: url, migrations: [Self.exampleSchema, addColumn])
        #expect(try await reopened.userVersion() == 2)
    }

    /// > Every table carries a `project_id` column — nothing assumes a single
    /// > project.
    @Test("A migration that leaves a table without project_id is rejected and rolled back")
    func migrationWithoutProjectIDIsRejected() async throws {
        let url = Self.temporaryDatabaseURL()
        let noProjectID = Migration(
            version: 1,
            name: "create a table missing project_id",
            sql: "CREATE TABLE missingColumn (id INTEGER PRIMARY KEY);"
        )

        var caughtError: DatabaseError?
        do {
            _ = try await Database(url: url, migrations: [noProjectID])
        } catch let error as DatabaseError {
            caughtError = error
        }

        #expect(caughtError == .missingProjectID(table: "missingColumn"))

        // Rolled back: the table must not exist afterward, and user_version
        // must still be 0 so a corrected migration 1 can be applied.
        let recovered = try await Database(url: url, migrations: [Self.exampleSchema])
        #expect(try await recovered.userVersion() == 1)
        #expect(try await Set(recovered.tableNames()) == ["exampleSessions", "exampleTokenRecords"])
    }

    /// Migrations must be supplied in strictly increasing version order.
    @Test("Out-of-order migration versions are rejected")
    func outOfOrderVersionsAreRejected() async throws {
        let url = Self.temporaryDatabaseURL()
        let first = Migration(
            version: 2,
            name: "second",
            sql: "CREATE TABLE a (id INTEGER PRIMARY KEY, project_id TEXT);"
        )
        let second = Migration(
            version: 1,
            name: "first",
            sql: "CREATE TABLE b (id INTEGER PRIMARY KEY, project_id TEXT);"
        )

        var caughtError: DatabaseError?
        do {
            _ = try await Database(url: url, migrations: [first, second])
        } catch let error as DatabaseError {
            caughtError = error
        }
        #expect(caughtError == .versionsNotStrictlyIncreasing)
    }

    /// > Foreign keys are enforced (`PRAGMA foreign_keys = ON`).
    @Test("An insert referencing a nonexistent parent row is rejected")
    func foreignKeysAreEnforced() async throws {
        let url = Self.temporaryDatabaseURL()
        let database = try await Database(url: url, migrations: [Self.exampleSchema])

        var caughtError: DatabaseError?
        do {
            try await database.execute(
                "INSERT INTO exampleTokenRecords (id, project_id, session_id) VALUES (1, 'p1', 999);"
            )
        } catch let error as DatabaseError {
            caughtError = error
        }

        // SQLite's own text for a foreign-key violation, distinct from every
        // other `execFailed` this call could otherwise raise (a syntax error,
        // a missing table) — so this fails if `PRAGMA foreign_keys = ON`
        // stops being applied even though the insert still throws for some
        // unrelated reason.
        #expect(caughtError == .execFailed(message: "FOREIGN KEY constraint failed"))
    }

    /// > Deletes cascade so removing a session removes its token records
    /// > (real deletion).
    @Test("Deleting a parent row cascades to its dependents")
    func deletesCascade() async throws {
        let url = Self.temporaryDatabaseURL()
        let database = try await Database(url: url, migrations: [Self.exampleSchema])

        try await database.execute("INSERT INTO exampleSessions (id, project_id) VALUES (1, 'p1');")
        try await database.execute("INSERT INTO exampleTokenRecords (id, project_id, session_id) VALUES (1, 'p1', 1);")
        #expect(try await database.rowCount(table: "exampleTokenRecords") == 1)

        try await database.execute("DELETE FROM exampleSessions WHERE id = 1;")

        #expect(try await database.rowCount(table: "exampleSessions") == 0)
        #expect(try await database.rowCount(table: "exampleTokenRecords") == 0)
    }
}
