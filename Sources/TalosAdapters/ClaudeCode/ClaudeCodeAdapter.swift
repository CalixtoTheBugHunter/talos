import Foundation

/// One instance is one session's whole life — ``ClaudeCodeAdapterRegistration``
/// hands out a fresh one per resolution, matching "each session resolves to
/// its own."
///
/// One ``AgentEventStream`` spans every `claude` process the session runs, one
/// per turn, since `-p` is headless and exits after each.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters
actor ClaudeCodeAdapter: AgentAdapter {
    private var configuration: AgentLaunchConfiguration?
    private var executablePath: String?
    private var hooks: ClaudeCodeHookConfiguration?
    private var mcpConfig: ClaudeCodeMCPConfiguration?
    private var continuation: AgentEventStream.Continuation?

    private var decoder = ClaudeCodeStreamDecoder()
    private var reporter = ClaudeCodeTokenReporter()
    private var sessionID: String?
    private var currentProcess: AgentProcess?
    /// The background task draining the current turn's process into the
    /// session stream. Cancelled by ``stop()`` so a stop ends the turn even
    /// while it is parked awaiting the next process event.
    private var turnTask: Task<Void, Never>?
    private var openRequestIDs: Set<String> = []
    private var lastOutput = ""
    private var hasFinished = false
    private var hasWarnedAboutCapabilities = false

    /// Set only in tests, to run against a stand-in for `claude` instead of
    /// resolving the real one from `PATH` — the suite installs nothing.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
    private let executableOverride: String?

    init(executableOverride: String? = nil) {
        self.executableOverride = executableOverride
    }

    // MARK: - The six capabilities

    func launch(_ configuration: AgentLaunchConfiguration) async throws -> AgentEventStream {
        guard self.configuration == nil else {
            throw AgentNotRunningError(fix: "This adapter already launched a session. Create a new one to run another.")
        }
        let executablePath = try executableOverride
            ?? ClaudeCodeInstallCheck.resolveExecutablePath(environment: configuration.environment)
        let hooks = try ClaudeCodeHookConfiguration()
        let mcpConfig = try ClaudeCodeMCPConfiguration(servers: configuration.mcpServers)

        self.configuration = configuration
        self.executablePath = executablePath
        self.hooks = hooks
        self.mcpConfig = mcpConfig
        // Seeds the first turn's own `--resume`, per `runTurn`'s
        // `sessionID.map { .resume } ?? .launch` choice — a resumed launch
        // never sends a fresh conversation. Overwritten with the same value
        // once the CLI's own `initialized` event confirms it.
        sessionID = configuration.resumeToken

        let (stream, continuation) = AgentEventStream.makeStream()
        self.continuation = continuation
        return stream
    }

    func send(_ prompt: AgentPrompt) async throws {
        try await runTurn(prompt: prompt)
    }

    func resolve(_ requestID: AgentPermissionRequest.ID, with decision: AgentPermissionDecision) async throws {
        guard let hooks else {
            throw AgentNotRunningError(fix: "Launch the adapter before resolving a permission request.")
        }
        guard openRequestIDs.contains(requestID) else {
            throw AgentNotRunningError(fix: "No permission request '\(requestID)' is waiting for a decision.")
        }
        // Wait for the launching turn's drain to reach its turn boundary before
        // recording the decision: that boundary is detected by the request
        // still being open at the clean exit, so removing it first would make
        // the drain read the exit as the session ending.
        await turnTask?.value
        guard !hasFinished else {
            throw AgentNotRunningError(fix: "The session has already ended; start a new one.")
        }
        let reason = decision == .allowed
            ? "Approved at the Talos Safeguards gate."
            : "Denied at the Talos Safeguards gate."
        try hooks.recordDecision(decision, reason: reason, for: requestID)
        openRequestIDs.remove(requestID)
        try await runTurn(prompt: AgentPrompt(text: ""))
    }

    func tokenUsage() async -> TokenReport {
        reporter.report()
    }

    func stop() async {
        guard !hasFinished else { return }
        turnTask?.cancel()
        if let currentProcess {
            await currentProcess.stop()
        }
        finish(AgentTermination(reason: .stopped, lastOutput: lastOutput))
    }

    // MARK: - Running one turn

    /// Spawns one `claude` process — a fresh launch, or `--resume` if this
    /// session already has a `session_id` — and drains it into the session's
    /// stream until it exits.
    ///
    /// A clean exit (code 0) ends the session, *except* while a deferred
    /// permission request is still pending — that exit is a turn boundary, and
    /// the session resumes when the gate's decision is carried back via
    /// `resolve`. Any other exit ends it. The deferred tool-use is drained from
    /// the `result` line before the exit event, so the two are distinguishable
    /// here by whether any request is still open.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
    private func runTurn(prompt: AgentPrompt) async throws {
        // Let the previous turn's drain finish before starting the next: a
        // resume is carried back the moment the consumer reads the pending
        // request, which can be before the prior turn's process has been torn
        // down and its `currentProcess` cleared. Nil on the first turn.
        await turnTask?.value
        guard let configuration, let hooks, let mcpConfig, let executablePath, !hasFinished else {
            throw AgentNotRunningError(fix: "Launch the adapter before sending a prompt.")
        }
        guard currentProcess == nil else {
            throw AgentNotRunningError(fix: "A turn is already running; wait for it to finish before sending another.")
        }

        let arguments = sessionID.map {
            ClaudeCodeInvocation.resume(
                sessionID: $0, prompt: prompt, settingsPath: hooks.settingsPath, mcpConfigPath: mcpConfig.configPath
            )
        } ?? ClaudeCodeInvocation.launch(
            prompt: prompt, settingsPath: hooks.settingsPath, mcpConfigPath: mcpConfig.configPath
        )

        let process = AgentProcess(executablePath: executablePath, arguments: arguments, configuration: configuration)
        currentProcess = process

        let events: AsyncThrowingStream<AgentProcessEvent, any Error>
        do {
            events = try await process.start()
        } catch {
            currentProcess = nil
            if sessionID == nil {
                finish(AgentTermination(reason: .failedToLaunch))
            }
            throw error
        }

        // Drain in the background so `send`/`resolve` return once the turn is
        // launched, not after it ends: the pipeline consumes the session
        // stream live — streaming output, applying the response-liveness
        // timeout, and honoring a stop — rather than only after the whole turn
        // has already run.
        turnTask = Task { await self.drainTurn(events) }
    }

    /// Drains one turn's process events into the session stream until the
    /// process ends. Runs as ``turnTask`` off the `send`/`resolve` call that
    /// started it, so the caller returns immediately.
    private func drainTurn(_ events: AsyncThrowingStream<AgentProcessEvent, any Error>) async {
        do {
            for try await event in events {
                switch event {
                case let .output(chunk):
                    handle(chunk)
                case let .terminated(termination):
                    currentProcess = nil
                    // A turn boundary only while a permission is pending — the
                    // stream stays open for the resume. Otherwise the exit ends
                    // the session.
                    if case .exited(0) = termination.reason, !openRequestIDs.isEmpty {
                        return
                    }
                    finish(termination)
                    return
                }
            }
        } catch {
            currentProcess = nil
            guard !hasFinished else { return }
            hasFinished = true
            continuation?.finish(throwing: error)
            hooks?.cleanUp()
            mcpConfig?.cleanUp()
        }
    }

    // MARK: - Turning stdout into events, and updating what a report needs

    private func handle(_ chunk: AgentOutputChunk) {
        switch chunk.channel {
        case .standardError:
            guard !chunk.text.isEmpty else { return }
            lastOutput = chunk.text
            continuation?.yield(.output(chunk))
        case .standardOutput:
            for line in decoder.takeLines(from: chunk.text) {
                guard let value = ClaudeCodeStreamDecoder.decode(line) else { continue }
                apply(value)
            }
        }
    }

    private func apply(_ value: ClaudeCodeStreamValue) {
        switch value {
        case let .initialized(sessionID, model, version, hasCapabilities):
            recordSessionStart(sessionID: sessionID, model: model, version: version, hasCapabilities: hasCapabilities)
        case let .usage(input, output):
            reporter.recordUsage(input: input, output: output)
        case .unrecognizedUsage:
            reporter.recordUnrecognizedUsage()
        case let .deferred(toolUseID, _, _, inputTokens, outputTokens):
            openRequestIDs.insert(toolUseID)
            if let inputTokens, let outputTokens {
                reporter.recordUsage(input: inputTokens, output: outputTokens)
            }
            emit(value)
        case .assistantText, .assistantToolUse, .permissionDenied:
            emit(value)
        case .ignored:
            break
        }
    }

    private func emit(_ value: ClaudeCodeStreamValue) {
        guard let event = ClaudeCodeEventMapper.agentEvent(for: value) else { return }
        if case let .output(chunk) = event {
            lastOutput = chunk.text
        }
        continuation?.yield(event)
    }

    private func recordSessionStart(sessionID: String, model: String, version: String, hasCapabilities: Bool) {
        self.sessionID = sessionID
        reporter.recordSessionStart(model: model, version: version)
        guard !hasCapabilities, !hasWarnedAboutCapabilities else { return }
        hasWarnedAboutCapabilities = true
        let message = ClaudeCodeInstallCheck.missingCapabilitiesDiagnostic(version: version)
        continuation?.yield(.output(AgentOutputChunk(channel: .standardError, text: message)))
    }

    /// The single choke point every termination path already passes through,
    /// so it is also the single place that attaches this run's own resume
    /// identifier — every caller above continues to construct a plain
    /// ``AgentTermination`` and never has to know `sessionID`.
    private func finish(_ termination: AgentTermination) {
        guard !hasFinished else { return }
        hasFinished = true
        let withResumeToken = AgentTermination(
            reason: termination.reason,
            lastOutput: termination.lastOutput,
            resumeToken: sessionID
        )
        continuation?.yield(.terminated(withResumeToken))
        continuation?.finish()
        hooks?.cleanUp()
        mcpConfig?.cleanUp()
    }
}
