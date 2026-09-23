import Foundation
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosPersistence
import TalosProjectLibrary
import TalosSafeguards
import TalosUI

/// The composition root a user-triggered sub-function — Assistant or
/// Automator — enters the shared session pipeline through, from a user
/// action. Both are the same pipeline: "that is the only difference between
/// them", so one composer serves both and `runSession` is sub-function
/// agnostic — only the intent's sub-function and the guideline it loads
/// differ.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
@MainActor
final class SessionComposer {
    /// A configuration problem in the chosen project's `.talos/` — never a
    /// pipeline failure, so it is reported before any agent launches.
    struct CompositionError: Error, CustomStringConvertible {
        let description: String
    }

    /// Everything a real session needs from the project's own `.talos/` tree,
    /// loaded once so a session start reads it as one value rather than five
    /// separate calls. `guideline` is the one loaded for the requesting
    /// sub-function.
    struct LoadedProject {
        let manifest: ProjectManifest
        let connectors: ConnectorsManifest
        let safeguards: SafeguardsDocument
        let guideline: GuidelineDocument
        let spec: SpecManifest
        let board: BoardManifest?
        let declaration: AgentDeclaration
    }

    /// The session the console currently shows, kept so a follow-up turn can
    /// resume it: its project and root are reused unchanged, and `resumeToken`
    /// is refreshed from each run's record so the next turn resumes the latest
    /// state. Set by every ``runSession(...)``, so a refresh run is continuable
    /// on the same terms as an Assistant or Automator one.
    struct ActiveSession {
        let root: URL
        let project: LoadedProject
        let subFunction: SubFunction
        var resumeToken: String?
    }

    /// Not `private`: the `+RunSession` extension sets it as each run starts and
    /// reads it to resume the current session on a follow-up turn.
    var activeSession: ActiveSession?

    /// A message the user submitted while a turn was running, held only until
    /// that turn tears down. Per [decision 100] a mid-turn message interrupts
    /// the running turn and supersedes it; this carries the message and the
    /// resume token captured at interrupt time (`nil` when the interrupted turn
    /// had no resumable session yet) across the teardown to the turn that
    /// delivers it. The latest submission wins — a newer interrupt replaces it.
    /// Not `private`: the `+RunSession` extension sets and drains it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
    var pendingSupersede: PendingSupersede?

    /// A superseding message and the session it resumes into, captured when a
    /// running turn is interrupted so the token survives the interrupted turn's
    /// teardown, which clears ``ActiveSession/resumeToken``.
    struct PendingSupersede {
        let text: String
        let resumeToken: String?
    }

    let database: Database
    /// Not `private`: the `+RunSession` extension wires and ends stop tracking.
    let stopCenter: SessionStopCenter
    /// The presenter a diverged board item's conflict prompt is shown through —
    /// the same instance the app view hosts, so a session's conflict check
    /// reaches the UI and blocks the session the way the gate does.
    let boardConflicts: BoardConflictPromptCenter
    var adapterRegistry = AgentAdapterRegistry()

    init(database: Database, stopCenter: SessionStopCenter, boardConflicts: BoardConflictPromptCenter) {
        self.database = database
        self.stopCenter = stopCenter
        self.boardConflicts = boardConflicts
        ClaudeCodeAdapterRegistration.register(into: &adapterRegistry)
    }

    /// Runs one Assistant session for `intentText` — read tier by default, per
    /// Sub-function-Assistant#autonomy.
    func startAssistantSession(
        projectRoot: URL,
        intentText: String,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter,
        sessionWillStart: (@MainActor () -> Void)? = nil
    ) async throws {
        try await startSession(
            subFunction: .assistant,
            projectRoot: projectRoot,
            intentText: intentText,
            console: console,
            deniedNotices: deniedNotices,
            sessionWillStart: sessionWillStart
        )
    }

    /// Runs one Automator session for `intentText` — write tier, deny-by-default,
    /// per Sub-function-Automator#autonomy. Every mutating tool call the agent
    /// attempts hits the same Safeguards gate this composer wires for every
    /// session; nothing here raises Automator's autonomy above that gate.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Automator#pipeline
    func startAutomatorSession(
        projectRoot: URL,
        intentText: String,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter,
        sessionWillStart: (@MainActor () -> Void)? = nil
    ) async throws {
        try await startSession(
            subFunction: .automator,
            projectRoot: projectRoot,
            intentText: intentText,
            console: console,
            deniedNotices: deniedNotices,
            sessionWillStart: sessionWillStart
        )
    }

    /// Scaffolds `.talos/` under `projectRoot` if it is entirely absent, loads
    /// the Project Library for `subFunction`, resolves the project's declared
    /// agent, and runs one session for `intentText`. Streams into `console`,
    /// which also renders every approval inline as the Session Console
    /// specifies, and surfaces a fail-closed or repeated denial through
    /// `deniedNotices`. The gate the run wires is identical for every
    /// sub-function; the tier of each action is the action's own, not the
    /// session's.
    private func startSession(
        subFunction: SubFunction,
        projectRoot: URL,
        intentText: String,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter,
        sessionWillStart: (@MainActor () -> Void)? = nil
    ) async throws {
        let root = projectRoot.standardizedFileURL
        let project = try Self.loadProject(at: root, subFunction: subFunction)
        let intent = Intent(
            content: intentText,
            source: .userText,
            project: project.manifest.id,
            requestingSubFunction: subFunction
        )
        _ = try await runSession(
            root: root,
            project: project,
            intent: intent,
            console: console,
            deniedNotices: deniedNotices,
            sessionWillStart: sessionWillStart
        )
    }

    static func loadProject(at root: URL, subFunction: SubFunction) throws -> LoadedProject {
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(".talos", isDirectory: true).path) {
            _ = try ProjectLibraryScaffolder.scaffold(projectRoot: root)
        }
        let manifest = try readProjectManifest(root: root)
        let agents = try readAgentsManifest(root: root)
        return try LoadedProject(
            manifest: manifest,
            connectors: readConnectorsManifest(root: root),
            safeguards: SafeguardsLoader.load(projectRoot: root),
            guideline: readGuideline(root: root, subFunction: subFunction),
            spec: SpecLoader.load(projectRoot: root),
            board: readBoardManifest(root: root),
            declaration: resolveAgent(project: manifest, agents: agents)
        )
    }

    /// The Spec Drive index for this project, read once into memory so the
    /// pipeline's synchronous retrieval never touches disk. Empty when the Spec
    /// Drive is declared absent or the index has not been built yet — building
    /// it is the agent's out-of-band work, tracked separately. A read that
    /// fails is treated as an empty index rather than a session failure: the
    /// index is derived and rebuildable, and retrieval labels the absence.
    private static func loadSpecSections(
        projectRoot: URL,
        project: ProjectIdentifier,
        spec: SpecManifest
    ) async -> [SpecSection] {
        guard case .locations = spec.specDrive else { return [] }
        let databaseURL = SpecIndexSchema.databaseURL(projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        do {
            let store = try await SpecIndexStore.open(projectRoot: projectRoot)
            return try await store.allSections(project: project)
        } catch {
            return []
        }
    }

    static func makePipeline(
        adapter: AnyAgentAdapterBox,
        gate: TieredSafeguardsGate,
        database: Database,
        project: LoadedProject,
        root: URL
    ) async -> SessionPipeline<AlwaysApprovedSafeguardsPreCheck, AnyAgentAdapterBox, TieredSafeguardsGate> {
        let specSections = await loadSpecSections(projectRoot: root, project: project.manifest.id, spec: project.spec)
        let assembler = ContextAssembler(
            specDriveSource: SpecDriveRetrieval(specDrive: project.spec.specDrive, sections: specSections),
            boardSource: BoardStateRetrieval(board: project.board, items: loadBoardItems(projectRoot: root)),
            memoriesSource: InertContextSource.memories
        )
        return SessionPipeline(
            assembler: assembler,
            preCheck: AlwaysApprovedSafeguardsPreCheck(),
            adapter: adapter,
            gate: gate,
            decisionLog: SQLiteGatedDecisionLog(database: database),
            recordWriter: SQLiteSessionRecordStore(database: database),
            memories: NoOpSessionMemoriesUpdatePort()
        )
    }

    /// `project.yaml`'s `agents:` list names which `agents.yaml` entry this
    /// project actually uses — the first one that resolves, since only one
    /// agent drives one session. Neither file is ever written here: both
    /// are user-owned configuration, and a project that has not configured
    /// either yet is reported rather than guessed at.
    private static func resolveAgent(project: ProjectManifest, agents: AgentsManifest) throws -> AgentDeclaration {
        guard !project.configuredAgents.isEmpty else {
            throw CompositionError(
                description: "No agent is declared in .talos/project.yaml's 'agents:' list. " +
                    "Add one — and a matching entry in .talos/agents.yaml — before starting a session."
            )
        }
        guard let declaration = project.configuredAgents.lazy
            .compactMap({ name in agents.agents.first { $0.name == name } })
            .first
        else {
            let named = project.configuredAgents.joined(separator: ", ")
            throw CompositionError(
                description: "None of the agents project.yaml names — \(named) — " +
                    "has a matching entry in .talos/agents.yaml."
            )
        }
        return declaration
    }

    private static func readProjectManifest(root: URL) throws -> ProjectManifest {
        let file = root.appendingPathComponent(".talos/project.yaml", isDirectory: false)
        let contents = try readFile(file)
        return try ProjectManifestParser.parse(contents: contents, file: file.path)
    }

    private static func readAgentsManifest(root: URL) throws -> AgentsManifest {
        let file = root.appendingPathComponent(".talos/agents.yaml", isDirectory: false)
        let contents = try readFile(file)
        return try AgentsManifestParser.parse(contents: contents, file: file.path)
    }

    private static func readConnectorsManifest(root: URL) throws -> ConnectorsManifest {
        let file = root.appendingPathComponent(".talos/connectors.yaml", isDirectory: false)
        let contents = try readFile(file)
        return try ConnectorsManifestParser.parse(contents: contents, file: file.path)
    }

    /// Nil when the project declares no board — `.talos/board.yaml` is optional,
    /// so its absence is a project without a board, not a failure to read one.
    private static func readBoardManifest(root: URL) throws -> BoardManifest? {
        let file = root.appendingPathComponent(".talos/board.yaml", isDirectory: false)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let contents = try readFile(file)
        return try BoardManifestParser.parse(contents: contents, file: file.path)
    }

    /// The board items for this project, read from the derived store the board
    /// refresh run leaves under `.talos/local/`. Empty until that run has stored
    /// them, or when the store was deleted — a rebuildable absence retrieval
    /// labels, never a session failure.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
    private static func loadBoardItems(projectRoot: URL) -> [BoardItem] {
        BoardStateReader().read(projectRoot: projectRoot)
    }

    private static func readGuideline(root: URL, subFunction: SubFunction) throws -> GuidelineDocument {
        let file = root.appendingPathComponent(
            ".talos/guidelines/\(subFunction.guidelineFileName)", isDirectory: false
        )
        let contents = try readFile(file)
        return try GuidelineDocumentParser.parse(contents: contents, subFunction: subFunction, file: file.path)
    }

    private static func readFile(_ url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CompositionError(description: "Could not read '\(url.path)': \(error).")
        }
    }
}
