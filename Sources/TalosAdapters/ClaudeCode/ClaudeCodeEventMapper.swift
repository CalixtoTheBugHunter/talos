import Foundation

// A decoded stdout line to the ``AgentEvent`` it is, if it is one. Session
// bookkeeping — the current session id, model, and token counts — is not this
// file's concern; ``ClaudeCodeAdapter`` reads the same ``ClaudeCodeStreamValue``
// for that, so this stays a pure translation with nothing to hold state in.
// § A tool call and a permission request are two events —
// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary

enum ClaudeCodeEventMapper {
    /// `nil` for a value that updates adapter state but is never itself shown —
    /// `.initialized`, `.usage`, `.unrecognizedUsage`, and `.ignored`.
    static func agentEvent(for value: ClaudeCodeStreamValue) -> AgentEvent? {
        switch value {
        case let .assistantText(text):
            return .output(AgentOutputChunk(channel: .standardOutput, text: text))
        case let .assistantToolUse(id, name, targets):
            return .toolCall(AgentToolCall(id: id, name: name, targets: targets))
        case let .permissionDenied(message):
            return .output(AgentOutputChunk(channel: .standardError, text: message))
        case let .deferred(toolUseID, toolName, targets, _, _):
            let request = AgentPermissionRequest(
                id: toolUseID,
                prompt: prompt(toolName: toolName, targets: targets),
                toolName: toolName
            )
            return .permissionRequest(request)
        case .initialized, .usage, .unrecognizedUsage, .ignored:
            return nil
        }
    }

    /// A factual restatement built from the same fields ``AgentToolCall``
    /// already carries. The deferred-tool-call protocol this adapter uses
    /// carries no rendered prompt text of its own to preserve, and an approval
    /// prompt "names the operation and the target, with counts and paths
    /// rather than a category" regardless of where the words came from.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    private static func prompt(toolName: String, targets: [String]) -> String {
        guard !targets.isEmpty else { return toolName }
        return "\(toolName) — \(targets.joined(separator: ", "))"
    }
}
