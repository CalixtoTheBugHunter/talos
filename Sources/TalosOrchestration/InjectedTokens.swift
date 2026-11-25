/// What Talos injected into one session's prompt, by source, in estimated
/// tokens. Kept per source so an overhead regression is diagnosable — the
/// Monitor can name the part that grew rather than only that the total did.
/// `framing` is the cost of marking droppable parts as data, which is real
/// Talos-added overhead on top of the parts' own content.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
public struct InjectedTokens: Equatable, Sendable {
    /// Estimated tokens per included part. A kind that was dropped or never
    /// assembled is absent, not zero.
    public let bySource: [ContextPartKind: Int]
    public let framing: Int

    public init(bySource: [ContextPartKind: Int] = [:], framing: Int = 0) {
        self.bySource = bySource
        self.framing = framing
    }

    /// Everything Talos added: the parts plus the framing around them.
    public var total: Int {
        bySource.values.reduce(framing, +)
    }

    /// The sources in a fixed order — ``ContextPartKind`` declaration order,
    /// framing last — so a surface listing them reads the same every time.
    public var orderedSources: [(label: String, tokens: Int)] {
        let parts = ContextPartKind.allCases.compactMap { kind in
            bySource[kind].map { (label: kind.rawValue, tokens: $0) }
        }
        return parts + [(label: Self.framingLabel, tokens: framing)]
    }

    /// The label the framing share is stored and shown under.
    public static let framingLabel = "framing"
}

public extension AssembledContext {
    /// This session's injected tokens by source. A resumed turn assembles no
    /// part, so every share is zero.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
    var injectedTokens: InjectedTokens {
        InjectedTokens(
            bySource: Dictionary(includedParts.map { ($0.kind, $0.estimatedTokens) }, uniquingKeysWith: +),
            framing: PromptDataFraming.overheadTokens(for: includedParts)
        )
    }
}
