import TalosProjectLibrary

/// The real ``SpecDriveContextSource`` for a project, resolved from its parsed
/// ``SpecManifest`` and the sections its local index holds. Fetching the wiki
/// and building that index is the agent's out-of-band work per
/// [decision 83](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions);
/// this reads the already-built index in memory and ranks it lexically, so the
/// synchronous `fetch` never touches disk or the network.
///
/// The caller gets a labeled ``ContextFragment/unavailable(reason:)`` whenever
/// there is nothing to inject — no Spec Drive, an empty index, or a question
/// that matched no section — so a thin retrieval is visible where the output is
/// read rather than silently shaping the answer.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
public struct SpecDriveRetrieval: SpecDriveContextSource {
    /// A self-imposed selectivity cap so retrieval injects relevant sections
    /// rather than the whole spec; the guideline's own ceiling is enforced on
    /// top of this by ``ContextAssembler``.
    public static let defaultTokenBudget = 1500

    private let specDrive: SpecDrive
    private let sections: [SpecSection]
    private let tokenBudget: Int

    public init(specDrive: SpecDrive, sections: [SpecSection] = [], tokenBudget: Int = defaultTokenBudget) {
        self.specDrive = specDrive
        self.sections = sections
        self.tokenBudget = tokenBudget
    }

    public func fetch(for intent: Intent) -> ContextFragment {
        switch specDrive {
        case .absent:
            return .unavailable(reason: "This project declares no Spec Drive.")
        case .locations:
            guard !sections.isEmpty else {
                return .unavailable(reason: "Spec Drive content is not indexed yet.")
            }
            let selected = SpecLexicalRanking.select(
                sections: sections,
                query: intent.content,
                tokenBudget: tokenBudget
            )
            guard !selected.isEmpty else {
                return .unavailable(reason: "No indexed spec section matched the question.")
            }
            return .available(render(selected))
        }
    }

    private func render(_ selected: [SpecSection]) -> String {
        selected.map(Self.render).joined(separator: "\n\n")
    }

    /// A DRAFT section is labeled where it is read as planned rather than
    /// current, so the agent never presents future work as today's rule.
    private static func render(_ section: SpecSection) -> String {
        var header = section.headingPath.joined(separator: " › ")
        if !section.anchor.isEmpty {
            header += " (#\(section.anchor))"
        }
        if section.isDraft {
            header += " — DRAFT: planned, not current"
        }
        return section.body.isEmpty ? header : "\(header)\n\(section.body)"
    }
}
