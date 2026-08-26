import Foundation

// One ``AgentEventStream`` spanning every `claude` process the session runs —
// one per turn, since `-p` is headless and exits after each.
// § Agent adapters —
// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters

/// The Claude Code CLI, adapted to ``AgentAdapter``. One instance is one
/// session's whole life — ``ClaudeCodeAdapterRegistration`` hands out a fresh
/// one per resolution, matching "each session resolves to its own."
actor ClaudeCodeAdapter: AgentAdapter {
    private var configuration: AgentLaunchConfiguration?
    private var executablePath: String?
    private var hooks: ClaudeCodeHookConfiguration?
    private var continuation: AgentEventStream.Continuation?

    private var decoder = ClaudeCodeStreamDecoder()
    private var reporter = ClaudeCodeTokenReporter()
    private var sessionID: String?
    private var currentProcess: AgentProcess?
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

        self.configuration = configuration
        self.executablePath = executablePath
        self.hooks = hooks

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
        // The protocol carries no reason; this text is only for the CLI's own hook.
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
    /// A clean exit (code 0) does not end the stream: both an ordinary turn
    /// and a deferred permission request end that way. Anything else does.
    private func runTurn(prompt: AgentPrompt) async throws {
        guard let configuration, let hooks, let executablePath, !hasFinished else {
            throw AgentNotRunningError(fix: "Launch the adapter before sending a prompt.")
        }
        guard currentProcess == nil else {
            throw AgentNotRunningError(fix: "A turn is already running; wait for it to finish before sending another.")
        }

        let arguments = sessionID.map {
            ClaudeCodeInvocation.resume(sessionID: $0, prompt: prompt, settingsPath: hooks.settingsPath)
        } ?? ClaudeCodeInvocation.launch(prompt: prompt, settingsPath: hooks.settingsPath)

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

        do {
            for try await event in events {
                switch event {
                case let .output(chunk):
                    handle(chunk)
                case let .terminated(termination):
                    currentProcess = nil
                    if case .exited(0) = termination.reason {
                        break
                    }
                    finish(termination)
                }
            }
        } catch {
            currentProcess = nil
            guard !hasFinished else { return }
            hasFinished = true
            continuation?.finish(throwing: error)
            hooks.cleanUp()
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

    private func finish(_ termination: AgentTermination) {
        guard !hasFinished else { return }
        hasFinished = true
        continuation?.yield(.terminated(termination))
        continuation?.finish()
        hooks?.cleanUp()
    }
}
