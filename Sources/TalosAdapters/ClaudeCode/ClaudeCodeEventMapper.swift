import Foundation
import TalosCore

/// A decoded stdout line to the ``AgentEvent`` it is, if it is one. Session
/// bookkeeping stays in ``ClaudeCodeAdapter``, so this is a pure translation
/// with no state of its own.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
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
        case let .deferred(toolUseID, toolName, targets, arguments, _, _):
            let request = AgentPermissionRequest(
                id: toolUseID,
                prompt: prompt(toolName: toolName, targets: targets),
                toolName: toolName,
                classifiedAction: classifiedAction(toolName: toolName, arguments: arguments),
                arguments: arguments
            )
            return .permissionRequest(request)
        case .initialized, .usage, .unrecognizedUsage, .ignored:
            return nil
        }
    }

    /// Built from ``AgentToolCall``'s own fields — the deferred-tool-call
    /// protocol carries no rendered prompt text to preserve.
    ///
    /// Not `private`: ``ClaudeCodeAdapter`` words a dropped call's request with
    /// it too, so a blocked call reads the same as the one that prompted.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    static func prompt(toolName: String, targets: [String]) -> String {
        guard !targets.isEmpty else { return toolName }
        return "\(toolName) — \(targets.joined(separator: ", "))"
    }

    /// The taxonomy action type a held call is, when it is one of the tools
    /// this adapter recognizes — so the gate classifies a board write at its
    /// [write tier](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#write-tier)
    /// rather than the irreversible default a raw provider tool name falls to,
    /// per [decision 96](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
    /// `github-mcp-server`'s consolidated `projects_write` selects its operation
    /// with `method`; a create adds an item, an update moves it. A method this
    /// adapter does not map returns `nil`, which the gate resolves at the
    /// most-restrictive tier — never a permissive guess.
    private static func classifiedAction(toolName: String, arguments: [String: String]) -> SafeguardsActionType? {
        guard toolName == "projects_write" else { return nil }
        switch arguments["method"] {
        case "add_project_item": return .boardItemCreate
        case "update_project_item": return .boardItemMove
        default: return nil
        }
    }
}
