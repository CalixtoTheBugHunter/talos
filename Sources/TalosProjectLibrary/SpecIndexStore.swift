import Foundation
import TalosPersistence

/// The schema of the derived Spec Drive index. Its own database, separate from
/// the session store, living at `.talos/local/spec-index.sqlite` — never
/// committed, rebuildable from the Spec Drive at any time.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
public enum SpecIndexSchema {
    /// The one migration this index database applies — the `spec_sections`
    /// table, carrying the `project_id` column every Talos table owes.
    public static let migration = Migration(
        version: 1,
        name: "create spec sections",
        sql: """
        CREATE TABLE spec_sections (
            id INTEGER PRIMARY KEY,
            project_id TEXT NOT NULL,
            location_url TEXT NOT NULL,
            page_title TEXT NOT NULL,
            heading_path TEXT NOT NULL,
            anchor TEXT NOT NULL,
            body TEXT NOT NULL,
            is_draft INTEGER NOT NULL,
            ordinal INTEGER NOT NULL
        );
        """
    )

    /// The index's on-disk home for one project — under `local/`, which the
    /// scaffolder gitignores.
    public static func databaseURL(projectRoot: URL) -> URL {
        projectRoot
            .appendingPathComponent(".talos/local", isDirectory: true)
            .appendingPathComponent("spec-index.sqlite", isDirectory: false)
    }
}

/// Reads and writes the derived Spec Drive index. Writing replaces a location's
/// sections wholesale — the index is rebuilt, not merged — because it is derived
/// data with a single source of truth.
public actor SpecIndexStore {
    private static let pathSeparator = "\u{001F}"

    private let database: Database

    /// Wraps an already-opened index database; use ``open(projectRoot:)`` to
    /// build one at the conventional `.talos/local/` path.
    public init(database: Database) {
        self.database = database
    }

    /// Opens (creating if necessary) the index database for `projectRoot`.
    public static func open(projectRoot: URL) async throws -> SpecIndexStore {
        let database = try await Database(
            url: SpecIndexSchema.databaseURL(projectRoot: projectRoot),
            migrations: [SpecIndexSchema.migration]
        )
        return SpecIndexStore(database: database)
    }

    /// Replaces every section stored for `project` at `locationURL` with
    /// `sections`, in one transaction, so a rebuild never leaves a half-updated
    /// index behind.
    public func replaceSections(
        _ sections: [SpecSection],
        project: ProjectIdentifier,
        locationURL: String
    ) async throws {
        try await database.execute("BEGIN IMMEDIATE;")
        do {
            try await database.run(
                "DELETE FROM spec_sections WHERE project_id = ? AND location_url = ?;",
                bindings: [.text(project.rawValue), .text(locationURL)]
            )
            for section in sections {
                try await database.run(
                    """
                    INSERT INTO spec_sections
                        (project_id, location_url, page_title, heading_path, anchor, body, is_draft, ordinal)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(project.rawValue),
                        .text(locationURL),
                        .text(section.pageTitle),
                        .text(section.headingPath.joined(separator: Self.pathSeparator)),
                        .text(section.anchor),
                        .text(section.body),
                        .int(section.isDraft ? 1 : 0),
                        .int(Int64(section.ordinal))
                    ]
                )
            }
            try await database.execute("COMMIT;")
        } catch {
            try? await database.execute("ROLLBACK;")
            throw error
        }
    }

    /// Every section indexed for `project`, in the order it was written — page
    /// order within the source, source order across pages.
    public func allSections(project: ProjectIdentifier) async throws -> [SpecSection] {
        let rows = try await database.query(
            """
            SELECT page_title, heading_path, anchor, body, is_draft, ordinal
            FROM spec_sections WHERE project_id = ? ORDER BY id;
            """,
            bindings: [.text(project.rawValue)]
        )
        return rows.compactMap(Self.section)
    }

    /// The columns the `allSections` query selects, in order — named so the
    /// decode reads by position without bare numeric indices.
    private enum Column: Int, CaseIterable {
        case pageTitle, headingPath, anchor, body, isDraft, ordinal
    }

    private static func section(from row: [DatabaseValue]) -> SpecSection? {
        guard row.count == Column.allCases.count,
              case let .text(pageTitle) = row[Column.pageTitle.rawValue],
              case let .text(headingPath) = row[Column.headingPath.rawValue],
              case let .text(anchor) = row[Column.anchor.rawValue],
              case let .text(body) = row[Column.body.rawValue],
              case let .int(isDraft) = row[Column.isDraft.rawValue],
              case let .int(ordinal) = row[Column.ordinal.rawValue]
        else { return nil }
        return SpecSection(
            pageTitle: pageTitle,
            headingPath: headingPath.components(separatedBy: pathSeparator),
            anchor: anchor,
            body: body,
            isDraft: isDraft != 0,
            ordinal: Int(ordinal)
        )
    }
}
