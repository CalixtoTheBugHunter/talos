/// Identifies which renderer an ``OutputElement`` needs, in the same open,
/// string-keyed shape as ``AgentAdapterRegistry``'s adapter names — a fixed
/// enum would close the set a *pluggable* renderer is required to stay open.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter
public struct OutputElementKind: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The one kind this issue registers a renderer for. Every other kind is
    /// unregistered until a later issue adds one.
    public static let markdown = Self(rawValue: "markdown")
}

/// One piece of agent output, typed by what it needs rendered as rather than
/// carrying only the raw text a Markdown assumption would imply.
public struct OutputElement: Equatable, Hashable, Sendable {
    public let kind: OutputElementKind
    public let payload: String

    public init(kind: OutputElementKind, payload: String) {
        self.kind = kind
        self.payload = payload
    }
}
