/// One row of a session transcript: a stable identity plus the
/// ``OutputElement`` it renders. `id` is assigned once, in arrival order, so
/// a finalized line's identity never changes — a `List` keyed on it diffs
/// only the row that actually changed rather than the whole transcript.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public struct SessionConsoleLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public var element: OutputElement

    public init(id: Int, element: OutputElement) {
        self.id = id
        self.element = element
    }
}
