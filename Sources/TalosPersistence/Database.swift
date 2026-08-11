import Foundation
import SQLite3

/// The local SQLite database.
///
/// An `actor` so every call is off the caller's thread — including the main
/// thread, per https://github.com/CalixtoTheBugHunter/talos/issues/38's
/// "Write path is off the main thread and does not block UI." A caller on
/// `@MainActor` reaches this type only through `await`, which hands the work
/// to the actor's own executor rather than running it inline.
public actor Database {
    /// `nonisolated(unsafe)` because `deinit` is `nonisolated` on an actor and
    /// `OpaquePointer` is not `Sendable`. Safe here specifically: every other
    /// access is through this actor's isolated methods, and `deinit` runs
    /// only once nothing else holds a reference to call one.
    private nonisolated(unsafe) var connection: OpaquePointer?

    /// Opens (creating if necessary) the database at `url`, turns on foreign
    /// key enforcement, and applies every migration in `migrations` that has
    /// not already run.
    ///
    /// - `PRAGMA foreign_keys = ON`:
    ///   https://github.com/CalixtoTheBugHunter/talos/issues/38 —
    ///   "Foreign keys are enforced."
    /// - Migrations run in ascending `version` order and only those with a
    ///   `version` greater than the database's current `PRAGMA user_version`
    ///   are applied — forward-only, and a fresh (empty) database starts at
    ///   `user_version` 0, so every migration runs on it in order.
    public init(url: URL, migrations: [Migration]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
            nil
        )
        guard openResult == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed"
            throw DatabaseError.openFailed(message: message)
        }

        do {
            try Self.rawExec(handle, "PRAGMA foreign_keys = ON;")
        } catch {
            sqlite3_close(handle)
            throw error
        }

        do {
            try Self.applyPendingMigrations(handle, migrations)
        } catch {
            sqlite3_close(handle)
            throw error
        }

        connection = handle
    }

    deinit {
        if let connection {
            sqlite3_close(connection)
        }
    }

    /// Runs `sql` with no result, inside the actor's isolation.
    public func execute(_ sql: String) throws {
        try Self.rawExec(connection, sql)
    }

    /// Returns the value of `PRAGMA user_version`.
    public func userVersion() throws -> Int32 {
        try Self.rawUserVersion(connection)
    }

    /// The name of every user table currently in the database.
    public func tableNames() throws -> [String] {
        try Self.rawTableNames(connection)
    }

    /// The number of rows in `table`. `table` is trusted, schema-controlled
    /// input — never a user-supplied string — the same trust boundary every
    /// call site in this actor already assumes for a table name.
    public func rowCount(table: String) throws -> Int {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM \(table);", -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.execFailed(message: Self.rawLastErrorMessage(connection))
        }
        sqlite3_step(statement)
        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - Migration runner

    /// A `static` operating on the raw handle rather than an instance method:
    /// this runs from `init`, before `self.connection` is set and before the
    /// actor's isolation exists to enter, so it cannot call an isolated
    /// method — the same reason `rawExec` below is `static`.
    private static func applyPendingMigrations(_ connection: OpaquePointer?, _ migrations: [Migration]) throws {
        for (earlier, later) in zip(migrations, migrations.dropFirst()) where earlier.version >= later.version {
            throw DatabaseError.versionsNotStrictlyIncreasing
        }

        let currentVersion = try rawUserVersion(connection)

        for migration in migrations where migration.version > currentVersion {
            try rawExec(connection, "BEGIN;")
            do {
                try rawExec(connection, migration.sql)
                try rawExec(connection, "PRAGMA user_version = \(migration.version);")
                try rawValidateProjectIDInvariant(connection)
                try rawExec(connection, "COMMIT;")
            } catch {
                try? rawExec(connection, "ROLLBACK;")
                throw error
            }
        }
    }

    /// https://github.com/CalixtoTheBugHunter/talos/issues/38 — "Every table
    /// carries a `project_id` column — nothing assumes a single project."
    private static func rawValidateProjectIDInvariant(_ connection: OpaquePointer?) throws {
        for table in try rawTableNames(connection) {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "PRAGMA table_info(\(table));"
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.execFailed(message: rawLastErrorMessage(connection))
            }
            var hasProjectID = false
            while sqlite3_step(statement) == SQLITE_ROW {
                let columnName = String(cString: sqlite3_column_text(statement, 1))
                if columnName == "project_id" {
                    hasProjectID = true
                    break
                }
            }
            guard hasProjectID else {
                throw DatabaseError.missingProjectID(table: table)
            }
        }
    }

    // MARK: - Raw SQLite helpers

    private static func rawExec(_ connection: OpaquePointer?, _ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "sqlite3_exec failed"
            sqlite3_free(errorPointer)
            throw DatabaseError.execFailed(message: message)
        }
    }

    private static func rawUserVersion(_ connection: OpaquePointer?) throws -> Int32 {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(connection, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.execFailed(message: rawLastErrorMessage(connection))
        }
        sqlite3_step(statement)
        return sqlite3_column_int(statement, 0)
    }

    private static func rawTableNames(_ connection: OpaquePointer?) throws -> [String] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';"
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.execFailed(message: rawLastErrorMessage(connection))
        }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            names.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        return names
    }

    private static func rawLastErrorMessage(_ connection: OpaquePointer?) -> String {
        String(cString: sqlite3_errmsg(connection))
    }
}
