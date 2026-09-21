import Foundation
import TalosOrchestration
import TalosProjectLibrary
import TalosUI

/// The board-state refresh run: Talos authors the intent, the agent reads the
/// board with its own MCP/CLI and writes the items into `.talos/local/`, and a
/// later session reads them. It enters the same pipeline a user's Assistant
/// session does (decision 85), so the agent's writes cross the gate. Nothing
/// here reads the board or spawns anything — the instruction is text.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
@MainActor
extension SessionComposer {
    /// What a refresh did. `noBoard` is a declared state, never an error.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#board
    enum BoardRefreshOutcome: Equatable {
        case noBoard
        /// `session` carries how the run ended, because the count alone cannot
        /// tell a refreshed store from a run that read nothing.
        case refreshed(itemCount: Int, session: SessionOutcomeClassification)
    }

    /// Reads the project's board through one agent run, then counts the items
    /// that landed — whatever the outcome, so a stopped or partly denied run
    /// leaves the store matching the file that exists.
    ///
    /// `sessionWillStart` fires once before the run, never for a no-board
    /// project — the caller must show the console during the run, since the
    /// agent's writes wait on an approval answered there.
    func refreshBoardState(
        projectRoot: URL,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter,
        sessionWillStart: @escaping @MainActor () -> Void
    ) async throws -> BoardRefreshOutcome {
        let root = projectRoot.standardizedFileURL
        let project = try Self.loadProject(at: root, subFunction: .assistant)
        guard let board = project.board else { return .noBoard }

        let request = BoardStateFetch.fetchRequest(for: board, projectRoot: root)
        try Self.emptyBoardDestination(of: request)
        let intent = Intent(
            content: request.instruction,
            source: .talosAuthored,
            project: project.manifest.id,
            requestingSubFunction: .assistant
        )
        let record = try await runSession(
            root: root,
            project: project,
            intent: intent,
            console: console,
            deniedNotices: deniedNotices,
            sessionWillStart: sessionWillStart
        )
        let items = BoardStateReader().read(projectRoot: root)
        return .refreshed(itemCount: items.count, session: record.outcome.classification)
    }

    /// Removes the items file before the run, so items deleted upstream do not
    /// survive as a stale store. Only the derived, gitignored file the fetch
    /// names.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
    private static func emptyBoardDestination(of request: BoardStateFetchRequest) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: request.destination.path) {
            try fileManager.removeItem(at: request.destination)
        }
        try fileManager.createDirectory(
            at: request.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
