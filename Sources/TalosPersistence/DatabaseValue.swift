/// One bound parameter or column value for a parameterized statement.
///
/// `Database/execute(_:)` is deliberately "trusted, schema-controlled text
/// only, never user-supplied input" — so a caller writing dynamic,
/// agent-derived, or otherwise untrusted values (a failure reason, a project
/// identifier, a count) needs a bound-parameter path instead of string
/// interpolation. This is that path's value type, closed over the four
/// SQLite storage classes ``Database`` actually needs.
public enum DatabaseValue: Equatable, Sendable {
    case text(String)
    case int(Int64)
    case double(Double)
    case null
}
