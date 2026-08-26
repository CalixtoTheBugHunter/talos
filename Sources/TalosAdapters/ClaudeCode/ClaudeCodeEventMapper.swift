import Foundation

// A decoded stdout line to the ``AgentEvent`` it is, if it is one. Session
// bookkeeping (session id, model, token counts) stays in ``ClaudeCodeAdapter``,
// so this is a pure translation with no state of its own.
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

    /// Built from ``AgentToolCall``'s own fields — the deferred-tool-call
    /// protocol carries no rendered prompt text to preserve.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    private static func prompt(toolName: String, targets: [String]) -> String {
        guard !targets.isEmpty else { return toolName }
        return "\(toolName) — \(targets.joined(separator: ", "))"
    }
}
