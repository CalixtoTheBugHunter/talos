import Foundation
import TalosCore
import TalosPersistence
import TalosProjectLibrary

/// Where what Talos injected into a session lives on disk — one
/// `session_overhead_sources` row per source, cascading on delete like the
/// token rows. The schema itself is ``SessionRecordsSchema/overheadSourcesMigration``.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
extension SQLiteSessionRecordStore {
    func insertOverheadSources(
        _ injected: InjectedTokens,
        project: ProjectIdentifier,
        sessionID: UUID
    ) async throws {
        for row in injected.orderedSources {
            try await database.run(
                """
                INSERT INTO session_overhead_sources (project_id, session_id, source, tokens)
                VALUES (?, ?, ?, ?);
                """,
                bindings: [
                    .text(project.rawValue), .text(sessionID.uuidString),
                    .text(row.label), .int(Int64(row.tokens))
                ]
            )
        }
    }

    /// Every overhead source row for the sessions of one project and range,
    /// grouped by session. A session with no rows is absent from the result.
    func injectedTokensBySession(
        project: ProjectIdentifier,
        from start: Date,
        to end: Date
    ) async throws -> [UUID: InjectedTokens] {
        let rows = try await database.query(
            """
            SELECT o.session_id, o.source, o.tokens
            FROM session_overhead_sources o
            JOIN session_records r ON r.id = o.session_id
            WHERE o.project_id = ? AND r.started_at >= ? AND r.started_at <= ?;
            """,
            bindings: [
                .text(project.rawValue),
                .double(start.timeIntervalSince1970),
                .double(end.timeIntervalSince1970)
            ]
        )
        var sources: [UUID: [ContextPartKind: Int]] = [:]
        var framing: [UUID: Int] = [:]
        for row in rows {
            guard
                row.count == OverheadColumn.allCases.count,
                case let .text(idText) = row[OverheadColumn.sessionID.rawValue],
                let id = UUID(uuidString: idText),
                case let .text(source) = row[OverheadColumn.source.rawValue],
                case let .int(tokens) = row[OverheadColumn.tokens.rawValue]
            else {
                throw SessionRecordsStoreError.malformedRow
            }
            if source == InjectedTokens.framingLabel {
                framing[id] = Int(tokens)
            } else if let kind = ContextPartKind(rawValue: source) {
                sources[id, default: [:]][kind] = Int(tokens)
            } else {
                throw SessionRecordsStoreError.malformedRow
            }
        }
        // Framing is written for every session that recorded sources, so its
        // key set is the set of sessions that were measured at all.
        return framing.reduce(into: [:]) { result, entry in
            result[entry.key] = InjectedTokens(bySource: sources[entry.key] ?? [:], framing: entry.value)
        }
    }

    /// The `SELECT` list of ``injectedTokensBySession(project:from:to:)``, in order.
    private enum OverheadColumn: Int, CaseIterable {
        case sessionID, source, tokens
    }
}
