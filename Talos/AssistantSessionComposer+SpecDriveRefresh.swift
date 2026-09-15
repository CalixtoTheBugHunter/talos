import Foundation
import TalosOrchestration
import TalosProjectLibrary
import TalosUI

/// The Spec Drive refresh run: Talos authors the intent, the agent fetches the
/// wiki with its own tools and writes Markdown into `.talos/local/`, and Talos
/// indexes those files. It enters the same pipeline a user's Assistant session
/// does (decision 85), so the agent's writes cross the gate. Nothing here
/// fetches or spawns — the instruction is text.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
@MainActor
extension AssistantSessionComposer {
    /// What a refresh did. `noSpecDrive` is a declared state, never an error.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-project-has-no-spec-drive
    enum SpecDriveRefreshOutcome: Equatable {
        case noSpecDrive
        /// `session` carries how the fetch run ended, because the counts alone
        /// cannot tell a refreshed index from a run that fetched nothing.
        case refreshed(pageCount: Int, sectionCount: Int, session: SessionOutcomeClassification)
    }

    /// Fetches every declared location through one agent run, then rebuilds the
    /// index from what landed — whatever the outcome, so a stopped or partly
    /// denied run leaves the index matching the files that exist.
    ///
    /// `sessionWillStart` fires once before the run, never for a no-Spec-Drive
    /// project — the caller must show the console during the run, since the
    /// agent's writes wait on an approval answered there.
    func refreshSpecDriveIndex(
        projectRoot: URL,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter,
        sessionWillStart: @MainActor () -> Void
    ) async throws -> SpecDriveRefreshOutcome {
        let root = projectRoot.standardizedFileURL
        let project = try Self.loadProject(at: root)
        let requests = SpecDriveProviders.fetchRequests(for: project.spec.specDrive, projectRoot: root)
        guard !requests.isEmpty else { return .noSpecDrive }

        sessionWillStart()
        try Self.emptyDestinations(of: requests)
        let intent = Intent(
            content: requests.map(\.instruction).joined(separator: "\n\n"),
            source: .talosAuthored,
            project: project.manifest.id,
            requestingSubFunction: .assistant
        )
        let record = try await runSession(
            root: root, project: project, intent: intent, console: console, deniedNotices: deniedNotices
        )

        let store = try await SpecIndexStore.open(projectRoot: root)
        let results = try await SpecDriveIndexBuilder().rebuild(
            requests: requests,
            project: project.manifest.id,
            store: store
        )
        return .refreshed(
            pageCount: results.reduce(0) { $0 + $1.pageCount },
            sectionCount: results.reduce(0) { $0 + $1.sectionCount },
            session: record.outcome.classification
        )
    }

    /// Empties each destination before the run, so a page deleted upstream does
    /// not survive as a stale file. Only the derived, gitignored directories the
    /// provider named.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
    private static func emptyDestinations(of requests: [SpecDriveFetchRequest]) throws {
        let fileManager = FileManager.default
        for request in requests {
            if fileManager.fileExists(atPath: request.destination.path) {
                try fileManager.removeItem(at: request.destination)
            }
            try fileManager.createDirectory(at: request.destination, withIntermediateDirectories: true)
        }
    }
}
