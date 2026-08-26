import Foundation

// What a spawned agent CLI reports as a process, below the parse that turns it
// into an ``AgentEvent``. A tool call and a permission request are absent on
// purpose: they come from reading the output, and a process that emitted them
// would put log-format knowledge in the layer that owns file descriptors.
// § Only the adapter layer spawns a process —
// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors

/// One event from a running agent process, in the order it happened.
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
