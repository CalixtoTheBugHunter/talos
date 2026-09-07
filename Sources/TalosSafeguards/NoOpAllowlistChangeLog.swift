/// An ``AllowlistChangeLog`` that writes nothing. Durable storage of the
/// allowlist change log is tracked separately from the store that produces
/// its entries, per ``AllowlistChangeLog``'s own doc comment; this type is
/// that honest absence made concrete for a caller that only ever reads
/// ``AllowlistStore/isAllowlisted(_:project:)`` and never grants or revokes
/// an entry itself.
public struct NoOpAllowlistChangeLog: AllowlistChangeLog {
    public init() {
        // Nothing to set up — this conformance holds no state.
    }

    public func record(_: AllowlistChangeEntry) async {
        // Deliberately discarded — see the type's own doc comment.
    }
}
