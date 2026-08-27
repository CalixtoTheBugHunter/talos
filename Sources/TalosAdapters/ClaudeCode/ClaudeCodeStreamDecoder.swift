import Foundation

/// What one decoded stdout line means, stripped to the flat, `Equatable`
/// values ``ClaudeCodeEventMapper`` turns into zero or more ``AgentEvent``.
///
/// `.ignored` covers every line that decoded fine but carries nothing Talos
/// surfaces — hook bookkeeping, `thinking_tokens`, and any unrecognized
/// `type`, so an unknown `type` on a future CLI release is silently skipped
/// rather than thrown.
enum ClaudeCodeStreamValue: Equatable, Sendable {
    case initialized(sessionID: String, model: String, version: String, hasCapabilities: Bool)
    case assistantText(String)
    case assistantToolUse(id: String, name: String, targets: [String])
    /// The CLI auto-denied because it could not show a prompt — the parallel
    /// tool-call batch case `defer` does not cover.
    case permissionDenied(message: String)
    /// `inputTokens`/`outputTokens` are `nil` when the line carried no `usage`
    /// — never treated as a failed turn.
    case deferred(toolUseID: String, toolName: String, targets: [String], inputTokens: Int?, outputTokens: Int?)
    case usage(input: Int, output: Int)
    /// A `result` line's `usage` did not decode as counts — a drift, distinct
    /// from a line that never arrived.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
    case unrecognizedUsage
    case ignored
}

/// Buffers stdout text across reads and hands complete lines to
/// ``decode(_:)``. A struct, not a stream of its own: ``ClaudeCodeAdapter``
/// owns one per running process and feeds it chunks as they arrive.
///
/// `--output-format stream-json` is one JSON object per line, on stdout only
/// — stderr is Claude Code's own plain-text diagnostics and is never parsed.
/// Tolerates a line split across chunks, and one that never becomes valid
/// JSON.
struct ClaudeCodeStreamDecoder {
    private var buffer = ""

    /// Appends `text` and returns every line it completed, in order. An
    /// incomplete trailing line stays buffered for the next call.
    mutating func takeLines(from text: String) -> [String] {
        buffer += text
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[buffer.startIndex ..< newline]))
            buffer.removeSubrange(buffer.startIndex ... newline)
        }
        return lines
    }

    /// The buffered remainder at end of output, which cannot become a
    /// complete line now. Empty when the stream ended cleanly.
    mutating func flush() -> String {
        let remainder = buffer
        buffer = ""
        return remainder
    }

    /// Decodes one stdout line, or returns `nil` for a line that is not valid
    /// JSON, or not a JSON object — the truncated-mid-write case a process
    /// killed while writing produces.
    static func decode(_ line: String) -> ClaudeCodeStreamValue? {
        guard !line.isEmpty else { return nil }
        guard let data = line.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        switch object["type"] as? String {
        case "system":
            return decodeSystem(object)
        case "assistant":
            return decodeAssistant(object)
        case "result":
            return decodeResult(object)
        default:
            return .ignored
        }
    }

    private static func decodeSystem(_ object: [String: Any]) -> ClaudeCodeStreamValue {
        switch object["subtype"] as? String {
        case "init":
            let sessionID = object["session_id"] as? String ?? ""
            let model = object["model"] as? String ?? ""
            let version = object["claude_code_version"] as? String ?? ""
            let hasCapabilities = object["capabilities"] != nil
            return .initialized(sessionID: sessionID, model: model, version: version, hasCapabilities: hasCapabilities)
        case "permission_denied":
            return .permissionDenied(message: object["message"] as? String ?? "Claude Code denied a tool call.")
        default:
            return .ignored
        }
    }

    private static func decodeAssistant(_ object: [String: Any]) -> ClaudeCodeStreamValue {
        guard let message = object["message"] as? [String: Any] else { return .ignored }
        guard let content = message["content"] as? [[String: Any]] else { return .ignored }
        for block in content {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    return .assistantText(text)
                }
            case "tool_use":
                if let id = block["id"] as? String, let name = block["name"] as? String {
                    let input = block["input"] as? [String: Any] ?? [:]
                    return .assistantToolUse(id: id, name: name, targets: targets(from: input))
                }
            default:
                continue
            }
        }
        return .ignored
    }

    private static func decodeResult(_ object: [String: Any]) -> ClaudeCodeStreamValue {
        let usage = object["usage"] as? [String: Any]
        let input = usage?["input_tokens"] as? Int
        let output = usage?["output_tokens"] as? Int

        if let deferred = deferredToolUse(from: object) {
            return .deferred(
                toolUseID: deferred.id,
                toolName: deferred.name,
                targets: targets(from: deferred.input),
                inputTokens: input,
                outputTokens: output
            )
        }
        guard usage != nil else { return .ignored }
        guard let input, let output else { return .unrecognizedUsage }
        return .usage(input: input, output: output)
    }

    /// The three fields ``decodeResult`` needs out of `deferred_tool_use` — a
    /// named type rather than a tuple, since a tuple here would carry three.
    private struct DeferredToolUse {
        let id: String
        let name: String
        let input: [String: Any]
    }

    private static func deferredToolUse(from object: [String: Any]) -> DeferredToolUse? {
        guard object["stop_reason"] as? String == "tool_deferred" else { return nil }
        guard let deferred = object["deferred_tool_use"] as? [String: Any] else { return nil }
        guard let id = deferred["id"] as? String else { return nil }
        guard let name = deferred["name"] as? String else { return nil }
        let input = deferred["input"] as? [String: Any] ?? [:]
        return DeferredToolUse(id: id, name: name, input: input)
    }

    /// What a tool call acts against, read from its own input rather than a
    /// per-tool schema Talos does not maintain. Every top-level string value
    /// is a target candidate, so a future tool's own field spelling still
    /// surfaces instead of being silently dropped.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    private static func targets(from input: [String: Any]) -> [String] {
        input.keys.sorted().compactMap { input[$0] as? String }
    }
}
