import Foundation

/// Which of the agent's two output channels a chunk arrived on. Kept apart
/// because an agent CLI's diagnostics and its answer are different things to
/// a reader, and merging them makes the second unattributable.
public enum AgentOutputChannel: String, Equatable, Hashable, Sendable {
    case standardOutput
    case standardError
}

/// One incremental piece of agent output, as it arrived. Never a buffered
/// whole: a console specified to show output "as it happens" cannot be fed
/// by an adapter that waits for completion.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public struct AgentOutputChunk: Equatable, Hashable, Sendable {
    public let channel: AgentOutputChannel
    public let text: String

    public init(channel: AgentOutputChannel, text: String) {
        self.channel = channel
        self.text = text
    }
}

/// The agent stating what it intends to do — what the Safeguards gate
/// intercepts before the action runs. Distinct from
/// ``AgentPermissionRequest``, which is the agent's CLI asking Talos a
/// question of its own accord.
public struct AgentToolCall: Equatable, Hashable, Sendable, Identifiable {
    /// Opaque to Talos and assigned by the adapter, so a later event can be
    /// tied back to this call without core learning a log format.
    public let id: String
    /// The tool the agent named, as the agent named it.
    ///
    /// Not an action type: mapping this onto the
    /// [taxonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy)
    /// the gate classifies against is the adapter's own work, for the same
    /// reason parsing its log format is — and the field that carries the
    /// result arrives with the classifier. Until then no core reader may
    /// switch on this string.
    public let name: String
    /// What the call acts against — paths, URLs, or a command — as the agent
    /// stated them. Empty when it stated none, which the gate classifies as
    /// an unstated target rather than as no target.
    ///
    /// A list because an approval prompt "names the operation and the target,
    /// with counts and paths rather than a category", and one string cannot
    /// carry four files without core parsing it back apart.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    public let targets: [String]

    public init(id: String, name: String, targets: [String] = []) {
        self.id = id
        self.name = name
        self.targets = targets
    }
}

/// The agent's CLI asking for consent of its own accord — a question put to
/// Talos, not an intent to run. The adapter surfaces it and carries back the
/// decision the gate produced; it never answers.
public struct AgentPermissionRequest: Equatable, Hashable, Sendable, Identifiable {
    /// The handle ``AgentAdapter/resolve(_:with:)`` carries the gate's
    /// decision back on.
    public let id: String
    /// The CLI's own wording, shown rather than paraphrased.
    public let prompt: String
    /// The tool the CLI is asking about, when it named one.
    public let toolName: String?

    public init(id: String, prompt: String, toolName: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.toolName = toolName
    }
}

/// The gate's answer to an ``AgentPermissionRequest``, carried back by
/// ``AgentAdapter/resolve(_:with:)``. An adapter never originates one of
/// these: an adapter-supplied answer produces an audit record naming a user
/// who never decided.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
public enum AgentPermissionDecision: String, Equatable, Hashable, Sendable {
    case allowed
    case denied
}

/// Why a run ended. `stopped` is the user's own act and `denied` is the
/// gate's, so neither is a failure — only ``exited`` with a non-zero code
/// and ``failedToLaunch`` are.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
public enum AgentTerminationReason: Equatable, Hashable, Sendable {
    /// The agent process exited on its own, with this status.
    case exited(code: Int32)
    /// ``AgentAdapter/stop()`` was called.
    case stopped
    /// The session ended because the gate denied and the work could not
    /// continue.
    case denied
    /// The agent never started.
    case failedToLaunch
}

/// How a run ended, attributed to the agent. Carries the agent's own last
/// output rather than a Talos-authored summary of it, because a summary of
/// someone else's failure is a guess presented as a diagnosis.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
public struct AgentTermination: Equatable, Hashable, Sendable {
    public let reason: AgentTerminationReason
    /// The last output the agent produced before ending, shown as-is. Empty
    /// when it produced none.
    public let lastOutput: String

    public init(reason: AgentTerminationReason, lastOutput: String = "") {
        self.reason = reason
        self.lastOutput = lastOutput
    }
}

/// One event on an ``AgentEventStream``, in the order it happened. A tool call
/// and a permission request are separately typed here rather than
/// distinguished by a field, because the gate's interception depends on the
/// distinction being structural.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
///
/// One ordered stream rather than one per concern: a tool call and a
/// permission request "arrive on the same stream in a similar shape", and the
/// console reads the *relative order* of output and tool calls to tell
/// waiting from streaming from running a tool.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#streaming-is-three-states-not-one
public enum AgentEvent: Equatable, Hashable, Sendable {
    /// The agent is producing output now.
    case output(AgentOutputChunk)
    /// The agent is acting. Reaches the gate before the action runs.
    case toolCall(AgentToolCall)
    /// The agent's CLI is asking Talos a question.
    case permissionRequest(AgentPermissionRequest)
    /// The last event of a run. The stream finishes after it.
    case terminated(AgentTermination)
}
