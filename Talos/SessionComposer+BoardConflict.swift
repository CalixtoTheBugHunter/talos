import Foundation
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import TalosUI

/// Builds the detect-and-ask resolver a session uses at the gate, and performs
/// the out-of-band "actual" read it needs — the app-layer half of decision 94.
/// The read is a separate Talos-authored board.read run, not the user's own
/// session, so it never reuses `runSession`'s single-slot Stop or its console.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
@MainActor
extension SessionComposer {
    /// The resolver for a project's board: it recognizes a `board.item.move`/
    /// `update`, compares the assembled "expected" state against a fresh
    /// "actual" read, and shows the conflict prompt on divergence.
    func makeBoardConflictResolver(root: URL, board: BoardManifest) -> DetectAndAskBoardConflictResolver {
        let expected = BoardStateReader().read(projectRoot: root)
        let center = boardConflicts
        return DetectAndAskBoardConflictResolver(
            recognizer: BoardWriteRecognizer(provider: board.provider),
            check: BoardConflictCheck(manifest: board),
            expected: expected,
            fetchActual: { [weak self] in await self?.boardActualItems(root: root) ?? expected },
            present: { presentation in await center.present(presentation) }
        )
    }

    /// A fresh board read, out of band: a Talos-authored `board.read` session
    /// with its own throwaway console, run inline so a Stop of the outer session
    /// cancels it too. Best-effort — on any failure it returns what is already on
    /// disk, so the conflict check degrades to "agree" (the write proceeds)
    /// rather than blocking a legitimate move on a read that could not complete.
    /// board.read is read tier, so the throwaway console is never prompted.
    func boardActualItems(root: URL) async -> [BoardItem] {
        let onDisk = BoardStateReader().read(projectRoot: root)
        do {
            let project = try Self.loadProject(at: root, subFunction: .assistant)
            guard let board = project.board else { return onDisk }
            let request = BoardStateFetch.fetchRequest(for: board, projectRoot: root)
            try? FileManager.default.removeItem(at: request.destination)
            let adapter = try AnyAgentAdapterBox(adapterRegistry.makeAdapter(named: project.declaration.adapter))
            let allowlist = try AllowlistStore(
                projectRoot: root,
                project: project.manifest.id,
                changeLog: NoOpAllowlistChangeLog()
            )
            let gate = TieredSafeguardsGate(
                allowlist: allowlist,
                approvalPrompt: SessionConsoleViewModel(),
                connectors: project.connectors
            )
            let pipeline = await Self.makePipeline(
                adapter: adapter, gate: gate, database: database, project: project, root: root
            )
            _ = await pipeline.run(
                intent: Intent(
                    content: request.instruction,
                    source: .talosAuthored,
                    project: project.manifest.id,
                    requestingSubFunction: .assistant
                ),
                guideline: project.guideline,
                safeguards: project.safeguards,
                connectors: project.connectors,
                launch: SessionLaunch(
                    agentName: project.declaration.name,
                    configuration: AgentLaunchConfiguration(
                        workingDirectory: root,
                        environment: SpawnedAgentEnvironment.resolve(),
                        model: project.declaration.model
                    )
                )
            )
            return BoardStateReader().read(projectRoot: root)
        } catch {
            return onDisk
        }
    }
}
