import Foundation
import SQLite3

/// The local SQLite database.
///
/// An `actor` so every call after construction is off the caller's thread,
/// including the main thread. Construction is off the caller's thread too,
/// because `init` is `async`: a synchronous actor `init` runs on the
/// *caller's* thread — actor isolation only takes effect once the instance
/// exists — so `init` here does the file I/O, the `sqlite3_open_v2` call,
/// and every pending migration on the actor's own executor instead.
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
    /// - `PRAGMA foreign_keys = ON` — foreign keys are enforced.
    /// - Migrations run in ascending `version` order and only those with a
    ///   `version` greater than the database's current `PRAGMA user_version`
    ///   are applied — forward-only, and a fresh (empty) database starts at
    ///   `user_version` 0, so every migration runs on it in order.
    public init(url: URL, migrations: [Migration]) async throws {
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

    /// `sql` is sent to SQLite with no parameter binding — trusted,
    /// schema-controlled text only, never user-supplied input.
    public func execute(_ sql: String) throws {
        try Self.rawExec(connection, sql)
    }

    /// Runs `sql` with `bindings` bound to its `?` placeholders, in order.
    /// The bound-parameter path for dynamic values — an agent-derived string,
    /// an identifier, a count — that ``execute(_:)`` forbids.
    public func run(_ sql: String, bindings: [DatabaseValue] = []) throws {
        let statement = try Self.prepare(connection, sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.execFailed(message: Self.rawLastErrorMessage(connection))
        }
    }

    /// Runs `sql` with `bindings` and returns every row, each as one
    /// ``DatabaseValue`` per column in column order.
    public func query(_ sql: String, bindings: [DatabaseValue] = []) throws -> [[DatabaseValue]] {
        let statement = try Self.prepare(connection, sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }

        var rows: [[DatabaseValue]] = []
        let columnCount = sqlite3_column_count(statement)
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                break
            }
            guard step == SQLITE_ROW else {
                throw DatabaseError.execFailed(message: Self.rawLastErrorMessage(connection))
            }
            var row: [DatabaseValue] = []
            for column in 0 ..< columnCount {
                row.append(Self.columnValue(statement, column))
            }
            rows.append(row)
        }
        return rows
    }

    /// `SQLITE_TRANSIENT`: tells SQLite to copy a bound string or blob rather
    /// than assume the caller keeps it alive past this call, since every
    /// value here is a short-lived Swift `String`.
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func prepare(
        _ connection: OpaquePointer?,
        _ sql: String,
        bindings: [DatabaseValue]
    ) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = rawLastErrorMessage(connection)
            sqlite3_finalize(statement)
            throw DatabaseError.execFailed(message: message)
        }
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result: Int32 = switch value {
            case let .text(text):
                sqlite3_bind_text(statement, position, text, -1, sqliteTransient)
            case let .int(int):
                sqlite3_bind_int64(statement, position, int)
            case let .double(double):
                sqlite3_bind_double(statement, position, double)
            case .null:
                sqlite3_bind_null(statement, position)
            }
            guard result == SQLITE_OK else {
                let message = rawLastErrorMessage(connection)
                sqlite3_finalize(statement)
                throw DatabaseError.execFailed(message: message)
            }
        }
        return statement
    }

    private static func columnValue(_ statement: OpaquePointer?, _ column: Int32) -> DatabaseValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            .int(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            .double(sqlite3_column_double(statement, column))
        case SQLITE_NULL:
            .null
        default:
            .text(String(cString: sqlite3_column_text(statement, column)))
        }
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

    /// Every table carries a `project_id` column — nothing assumes a single project.
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
