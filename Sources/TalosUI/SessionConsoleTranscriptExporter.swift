import TalosAdapters
import TalosCore
import TalosSafeguards

/// "Export produces a readable file (Markdown) including tool calls and
/// approvals." Renders exactly what ``SessionConsoleView`` shows — output as
/// prose, a tool call as its name, targets, and resolved outcome — so the
/// export is the transcript the user already read, never a second summary of
/// it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public enum SessionConsoleTranscriptExporter {
    /// `lines` may be live, unredacted agent output — this view has no
    /// guarantee it was ever written to (and redacted by)
    /// `SQLiteSessionRecordStore`, so every line is redacted again here.
    /// "Export never includes secret values."
    public static func markdown(for lines: [SessionConsoleLine]) -> String {
        let header = "# Talos session transcript\n\n"
        let body = lines.map(Self.markdown(for:)).joined(separator: "\n\n")
        return header + body
    }

    private static func markdown(for line: SessionConsoleLine) -> String {
        switch line.content {
        case let .output(element):
            LogRedaction.redacted(element.payload)
        case let .toolCall(call):
            Self.markdown(for: call)
        }
    }

    private static func markdown(for call: SessionConsoleToolCall) -> String {
        let name = LogRedaction.redacted(call.name)
        let targets = call.targets.map(LogRedaction.redacted)
        let summary = targets.isEmpty ? name : "\(name) \(targets.joined(separator: ", "))"
        switch call.approval {
        case .notGated, .pending:
            return "> **Tool:** \(summary)"
        case let .resolved(_, tier, outcome):
            return "> **Tool:** \(summary) — \(Self.outcomeLabel(outcome)) (\(Self.tierLabel(tier)))"
        }
    }

    private static func outcomeLabel(_ outcome: AgentPermissionDecision) -> String {
        switch outcome {
        case .allowed: "Allowed"
        case .denied: "Denied"
        }
    }

    private static func tierLabel(_ tier: SafeguardsTier) -> String {
        switch tier {
        case .read: "Read"
        case .write: "Write"
        case .irreversible: "Irreversible"
        }
    }
}
