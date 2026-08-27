import Foundation

/// One event from a running agent process, in the order it happened. A tool
/// call and a permission request are absent on purpose: they come from
/// reading the output, and a process that emitted them would put log-format
/// knowledge in the layer that owns file descriptors.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
///
/// The payloads are ``AgentOutputChunk`` and ``AgentTermination`` rather than
/// types of their own, so an adapter maps a process event onto an ``AgentEvent``
/// instead of modelling the same two facts twice.
enum AgentProcessEvent: Equatable, Hashable, Sendable {
    /// Bytes the process wrote, on the channel it wrote them to, decoded as
    /// far as they decode. Never a buffered whole.
    case output(AgentOutputChunk)
    /// The last event of a run. The stream finishes after it.
    case terminated(AgentTermination)
}

/// Thrown when a process could not be started at all, so no stream exists to
/// carry an ``AgentTerminationReason/failedToLaunch`` on.
///
/// Names the executable, the `errno`, and the fix: the path came from a file a
/// user wrote by hand, and not-installed, not-executable, and wrong-path are
/// each fixed differently.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
struct AgentSpawnFailure: Error, Equatable, Sendable {
    /// The executable that could not be started, as it was given.
    let executablePath: String
    /// Kept as the number the system gave, so the message below is a
    /// translation rather than a replacement.
    let code: Int32
    /// What to change to fix it, stated as an instruction.
    let fix: String

    init(executablePath: String, code: Int32) {
        self.executablePath = executablePath
        self.code = code
        let reason = String(cString: strerror(code))
        fix = "Could not start '\(executablePath)': \(reason). " +
            "Check that the agent CLI is installed and that 'command:' in .talos/agents.yaml names its path."
    }
}

/// Thrown from the stream when reading one of the child's pipes failed inside
/// Talos.
///
/// > The stream throws only for a Talos-side read failure. The agent's own
/// > abnormal exit is a `terminated` event carrying `.exited(code:)` and the
/// > agent's own last output
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing
///
/// So this is the one thing that throws, and it is Talos's own failure rather
/// than a diagnosis of the agent's.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
struct AgentReadFailure: Error, Equatable, Sendable {
    /// Which of the child's two pipes could not be read.
    let channel: AgentOutputChannel
    /// The number the system gave, so `message` is a translation of it.
    let code: Int32
    /// Names Talos as the party that failed, because it is.
    let message: String

    init(channel: AgentOutputChannel, code: Int32) {
        self.channel = channel
        self.code = code
        message = "Talos could not read the agent's \(channel) stream: \(String(cString: strerror(code)))."
    }
}
