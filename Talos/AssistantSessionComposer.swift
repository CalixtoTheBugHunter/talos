import Foundation
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosPersistence
import TalosProjectLibrary
import TalosSafeguards
import TalosUI

/// The composition root Assistant enters the shared session pipeline
/// through, from a user action. Nothing before this issue ever called
/// `SessionPipeline.run` — every collaborator it wires already exists and
/// is exercised in isolation elsewhere; this type is only the wiring.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Assistant#pipeline
@MainActor
final class AssistantSessionComposer {
    /// A configuration problem in the chosen project's `.talos/` — never a
    /// pipeline failure, so it is reported before any agent launches.
    struct CompositionError: Error, CustomStringConvertible {
        let description: String
    }

    /// Everything a real Assistant session needs from the project's own
    /// `.talos/` tree, loaded once so `startAssistantSession` reads it as
    /// one value rather than five separate calls.
    private struct LoadedProject {
        let manifest: ProjectManifest
        let connectors: ConnectorsManifest
        let safeguards: SafeguardsDocument
        let guideline: GuidelineDocument
        let declaration: AgentDeclaration
    }

    private let database: Database
    private let stopCenter: SessionStopCenter
    private var adapterRegistry = AgentAdapterRegistry()

    init(database: Database, stopCenter: SessionStopCenter) {
        self.database = database
        self.stopCenter = stopCenter
        ClaudeCodeAdapterRegistration.register(into: &adapterRegistry)
    }

    /// Scaffolds `.talos/` under `projectRoot` if it is entirely absent,
    /// loads the Project Library, resolves the project's declared agent, and
    /// runs one Assistant session for `intentText` — read tier by default,
    /// per Sub-function-Assistant#autonomy. Streams into `console`, which
    /// also renders every approval inline as the Session Console specifies,
    /// and surfaces a fail-closed or repeated denial through `deniedNotices`.
    func startAssistantSession(
        projectRoot: URL,
        intentText: String,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter
    ) async throws {
        let root = projectRoot.standardizedFileURL
        let project = try Self.loadProject(at: root)
        let adapter = try AnyAgentAdapterBox(adapterRegistry.makeAdapter(named: project.declaration.adapter))
        let allowlist = try AllowlistStore(
            projectRoot: root,
            project: project.manifest.id,
            changeLog: NoOpAllowlistChangeLog()
        )
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: console, connectors: project.connectors)
        let pipeline = Self.makePipeline(adapter: adapter, gate: gate, database: database)

        let intent = Intent(
            content: intentText,
            source: .userText,
            project: project.manifest.id,
            requestingSubFunction: .assistant
        )
        let launch = SessionLaunch(
            agentName: project.declaration.name,
            configuration: AgentLaunchConfiguration(
                workingDirectory: root,
                environment: SpawnedAgentEnvironment.resolve()
            )
        )

        console.sessionStarted()
        // Run the pipeline in a task the Stop control cancels: a stop reaches
        // the pipeline as cancellation, which kills the agent at any suspension
        // the session can be sitting at — including "Waiting for the agent to
        // respond." Tracking begins before the first await and ends however the
        // session does, so Stop is reachable throughout and never after.
        // https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
        let sessionTask = Task {
            await pipeline.run(
                intent: intent,
                guideline: project.guideline,
                safeguards: project.safeguards,
                connectors: project.connectors,
                launch: launch,
                observer: { [console] event in await console.handle(event) },
                tokenObserver: { [console] update in await console.updateTokenUsage(update) },
                onDenial: { [deniedNotices] action, prompt in
                    await deniedNotices.notify(action: action, requestPrompt: prompt)
                }
            )
        }
        stopCenter.beginTracking { sessionTask.cancel() }
        defer { stopCenter.sessionEnded() }
        let record = await sessionTask.value
        // The pipeline's pre-stream terminal paths (a launch that failed, a
        // pre-check denial) emit no `.terminated` to the observer, so tell the
        // console the final outcome directly; a no-op once the stream reported
        // the end, so a streamed session keeps what it observed.
        console.sessionConcluded(record.outcome)
    }

    private static func loadProject(at root: URL) throws -> LoadedProject {
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(".talos", isDirectory: true).path) {
            _ = try ProjectLibraryScaffolder.scaffold(projectRoot: root)
        }
        let manifest = try readProjectManifest(root: root)
        let agents = try readAgentsManifest(root: root)
        return try LoadedProject(
            manifest: manifest,
            connectors: readConnectorsManifest(root: root),
            safeguards: SafeguardsLoader.load(projectRoot: root),
            guideline: readGuideline(root: root, subFunction: .assistant),
            declaration: resolveAgent(project: manifest, agents: agents)
        )
    }

    private static func makePipeline(
        adapter: AnyAgentAdapterBox,
        gate: TieredSafeguardsGate,
        database: Database
    ) -> SessionPipeline<AlwaysApprovedSafeguardsPreCheck, AnyAgentAdapterBox, TieredSafeguardsGate> {
        let assembler = ContextAssembler(
            specDriveSource: InertContextSource.specDrive,
            boardSource: InertContextSource.board,
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
