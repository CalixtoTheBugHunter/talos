/// One row of a session transcript: a stable identity plus the content it
/// renders. `id` is assigned once, in arrival order, so a finalized line's
/// identity never changes — a `List` keyed on it diffs only the row that
/// actually changed rather than the whole transcript. A ``SessionConsoleToolCall``
/// row is the exception that is expected to change again in place, when its
/// `approval` moves from `.none` to `.pending` to `.resolved`; it keeps the
/// same guarantee — one row diffs, not the transcript.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public struct SessionConsoleLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public var content: SessionConsoleLineContent

    public init(id: Int, content: SessionConsoleLineContent) {
        self.id = id
        self.content = content
    }
}

/// What a ``SessionConsoleLine`` shows: agent output, dispatched through the
/// pluggable ``OutputRendererRegistry``, or a tool call the agent announced —
/// two different ``AgentEvent`` cases, kept apart here for the same reason
/// they are kept apart on the stream.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
public enum SessionConsoleLineContent: Equatable, Sendable {
    case output(OutputElement)
    case toolCall(SessionConsoleToolCall)
}
