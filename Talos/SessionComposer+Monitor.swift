import Foundation
import TalosOrchestration
import TalosPersistence
import TalosUI

extension SessionComposer {
    /// The Monitor's records for a project folder over an interval, read from
    /// the local SQLite store. Reads `.talos/project.yaml` for the project's
    /// identifier and never scaffolds: looking at a folder is not adding it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
    nonisolated static func monitorRecords(
        database: Database,
        projectRoot: URL,
        interval: DateInterval
    ) async throws -> [StoredSessionRecord] {
        let talos = projectRoot.appendingPathComponent(".talos", isDirectory: true)
        guard FileManager.default.fileExists(atPath: talos.path) else {
            throw MonitorNotATalosProjectError()
        }
        let manifest = try readProjectManifest(root: projectRoot)
        return try await SQLiteSessionRecordStore(database: database)
            .records(project: manifest.id, from: interval.start, to: interval.end)
    }
}
