/// Type-erases any ``AgentAdapter`` behind one concrete, `Sendable` box.
///
/// An adapter resolved by name from ``AgentAdapterRegistry`` is necessarily
/// `any AgentAdapter` — the name is not known until a project's
/// `agents.yaml` names it — and Swift does not let an existential satisfy a
/// generic `Adapter: AgentAdapter` constraint such as a session pipeline's.
/// This box is that seam: it forwards each of the six capabilities
/// unchanged and adds no behavior of its own.
public struct AnyAgentAdapterBox: AgentAdapter {
    private let base: any AgentAdapter

    public init(_ base: any AgentAdapter) {
        self.base = base
    }

    public func launch(_ configuration: AgentLaunchConfiguration) async throws -> AgentEventStream {
        try await base.launch(configuration)
    }

    public func send(_ prompt: AgentPrompt) async throws {
        try await base.send(prompt)
    }

    public func resolve(_ requestID: AgentPermissionRequest.ID, with decision: AgentPermissionDecision) async throws {
        try await base.resolve(requestID, with: decision)
    }

    public func tokenUsage() async -> TokenReport {
        await base.tokenUsage()
    }

    public func stop() async {
        await base.stop()
    }
}
