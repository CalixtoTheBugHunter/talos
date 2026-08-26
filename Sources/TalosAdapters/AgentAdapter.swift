import Foundation

// The adapter contract: the six capabilities every supported agent declares,
// and nothing else. A seventh would be agent-specific knowledge entering a
// contract every future adapter must then satisfy.
// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters
// https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-easiest-high-value-contribution-an-agent-adapter

/// Where and in what environment an agent runs. Both are explicit because a
/// child that inherits an ambient working directory or environment is a child
/// whose inputs nobody declared.
///
/// What is *not* here is how a particular agent is invoked — the executable,
/// its arguments, its flags. Those are the adapter's own knowledge, and
/// nothing in Talos core decides them.
public struct AgentLaunchConfiguration: Equatable, Hashable, Sendable {
    /// The directory the agent runs in — the project root.
    public let workingDirectory: URL
    /// The exact environment handed to the child. Nothing is inherited that
    /// is not named here.
    public let environment: [String: String]

    public init(workingDirectory: URL, environment: [String: String] = [:]) {
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

/// The prompt Talos assembled, for the adapter to transport unchanged.
///
/// A named type rather than a bare `String` so that "the adapter does not
/// edit, summarize, re-order, or append to it" is a statement about a value
/// with one field, not a convention about a parameter.
/// § What is persistent context and what is not —
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
public struct AgentPrompt: Equatable, Hashable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// The ordered sequence of ``AgentEvent`` a run produces.
///
/// An async sequence rather than a callback: the console consumes output as
/// it arrives and nothing polls for it. It throws for a Talos-side read
/// failure only — the agent's own abnormal exit is an
/// ``AgentEvent/terminated(_:)`` event, because a crash is not an error Talos
/// may paraphrase and is not a denial.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
public typealias AgentEventStream = AsyncThrowingStream<AgentEvent, any Error>

/// Thrown when an adapter is asked to act on a run that is not in progress —
/// not yet launched, or already terminated.
public struct AgentNotRunningError: Error, Equatable, Sendable {
    public let fix: String

    public init(fix: String) {
        self.fix = fix
    }
}

/// One supported agent, as a thin adapter.
///
/// The protocol declares exactly the six capabilities § Agent adapters
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters
/// specifies, and each member below names which one it discharges. Capability
/// four takes two members — the typed events that detect, and the path that
/// carries the gate's decision back — which discharges one obligation rather
/// than adding a seventh.
///
/// The protocol names no agent and no model provider. One that named an agent
/// would have made agent knowledge core knowledge, which is the cost
/// "adding an agent means writing one adapter, never touching Talos core"
/// exists to prevent.
public protocol AgentAdapter: Sendable {
    /// **How to launch it**, and the stream **how to stream its output**
    /// delivers on.
    ///
    /// The stream is returned by the launch rather than fetched afterwards,
    /// so no event can arrive before there is somewhere to put it. The spawn
    /// happens here and nowhere else in Talos.
    /// § Only the adapter layer spawns a process —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    func launch(_ configuration: AgentLaunchConfiguration) async throws -> AgentEventStream

    /// **How to pass a prompt.** Transports `prompt` verbatim.
    func send(_ prompt: AgentPrompt) async throws

    /// The return half of **how to detect a tool call or a permission
    /// request**: carries the gate's `decision` back to the request the agent
    /// raised.
    ///
    /// The adapter never originates a decision, never writes an acceptance to
    /// the child itself, and never launches its CLI in a mode that suppresses
    /// or pre-approves the CLI's own prompts.
    /// § A tool call and a permission request are two events —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    func resolve(_ requestID: AgentPermissionRequest.ID, with decision: AgentPermissionDecision) async throws

    /// **How to report token usage** — as values, for the run so far.
    ///
    /// Never throws and never fails: a run whose usage could not be parsed
    /// reports ``TokenReport/unavailable(_:)``, because losing an observation
    /// is not losing the right to work.
    func tokenUsage() async -> TokenReport

    /// **How to stop it.** The agent process and every process it started are
    /// dead when this returns.
    ///
    /// Neither throwing nor returning a value, deliberately: there is no
    /// shape here for a partial stop, a request the agent may ignore, or a
    /// signal that was merely sent.
    ///
    /// > A surviving child is a failed stop, not a partial one.
    ///
    /// It is callable at any point a run is live, including while a
    /// permission request waits unresolved — the state a session sits in
    /// longest, and the one where the user most wants out. The run ends with
    /// ``AgentTerminationReason/stopped`` and the stream finishes.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    func stop() async
}
