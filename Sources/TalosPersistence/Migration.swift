/// One forward-only schema step, applied at most once and never reordered.
public struct Migration: Sendable {
    /// Matches SQLite's `PRAGMA user_version`, which the runner uses to track
    /// which migrations have already been applied.
    public let version: Int32
    public let name: String
    public let sql: String

    public init(version: Int32, name: String, sql: String) {
        self.version = version
        self.name = name
        self.sql = sql
    }
}

/// Failures the persistence layer raises rather than repairs or ignores.
public enum DatabaseError: Error, Equatable {
    /// Opening or creating the database file failed.
    case openFailed(message: String)
    /// A statement failed; `message` is SQLite's own error text.
    case execFailed(message: String)
    /// A migration created or left a table with no `project_id` column —
    /// every table needs one from day one, even while there is only ever
    /// one project.
    case missingProjectID(table: String)
    /// The supplied migrations were not in strictly increasing version order.
    case versionsNotStrictlyIncreasing
}
