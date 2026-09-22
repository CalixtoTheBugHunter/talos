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
            let classification = classify(toolName: toolName, arguments: arguments)
            let request = AgentPermissionRequest(
                id: toolUseID,
                prompt: prompt(toolName: toolName, targets: targets),
                toolName: toolName,
                connectorAccess: classification.connectorAccess,
                classifiedAction: classification.action,
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

    /// The taxonomy classification of a held call, when it is one of the tools
    /// this adapter recognizes — so the gate classifies a board write or a git
    /// commit at its [write tier](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#write-tier)
    /// rather than the irreversible default a raw provider tool name falls to,
    /// per [decision 96](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
    /// Both members `nil` for a call this adapter does not classify, which the
    /// gate resolves at the most-restrictive tier — never a permissive guess.
    private typealias HeldCallClassification = (action: SafeguardsActionType?, connectorAccess: AgentConnectorAccess?)

    private static func classify(toolName: String, arguments: [String: String]) -> HeldCallClassification {
        // `github-mcp-server`'s consolidated `projects_write` selects its
        // operation with `method`; a create adds an item, an update moves it.
        if toolName == "projects_write" {
            switch arguments["method"] {
            case "add_project_item": return (.boardItemCreate, nil)
            case "update_project_item": return (.boardItemMove, nil)
            default: return (nil, nil)
            }
        }
        // Claude Code runs `git`/`gh` through `Bash`, so the operation lives in
        // the command string, not the tool name.
        if toolName == "Bash", let command = arguments["command"] {
            return gitClassification(for: command)
        }
        return (nil, nil)
    }

    /// A recognized git operation's classification: its taxonomy type, plus a
    /// repo-remote connector access the gate resolves against `connectors.yaml`
    /// for a remote op. An unrecognized command carries neither.
    private static func gitClassification(for command: String) -> HeldCallClassification {
        guard let recognized = GitCommandRecognizer.recognize(command: command) else { return (nil, nil) }
        guard recognized.reachesRemote else { return (recognized.action, nil) }
        let access = AgentConnectorAccess(
            target: recognized.explicitRemoteURL ?? "",
            verb: .write,
            isRepoRemote: true
        )
        return (recognized.action, access)
    }
}
