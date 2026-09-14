import TalosProjectLibrary

/// Selects the Spec Drive sections most relevant to a question by **lexical**
/// overlap — term frequency, weighting heading matches over body matches — and
/// stops once a token budget is reached, so retrieval is selective rather than
/// injecting the whole spec. Ranking is lexical by decision, not as a stopgap:
/// a question phrased unlike the spec's own wording retrieves less, and Talos
/// does not paper over the gap by guessing synonyms.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
enum SpecLexicalRanking {
    /// A heading-term match counts for more than a body-term match, since a
    /// section whose heading names the topic is a better answer than one that
    /// merely mentions it in passing.
    private static let headingWeight = 3

    /// Tokens shorter than this are dropped as noise — they carry little
    /// lexical signal and inflate scores on common short words.
    private static let minimumTermLength = 2

    /// The sections of `sections` that lexically match `query`, highest score
    /// first among those kept, then returned in the index's own order for
    /// coherent reading. Selection stops once `tokenBudget` is reached; a query
    /// that matches nothing returns nothing.
    static func select(sections: [SpecSection], query: String, tokenBudget: Int) -> [SpecSection] {
        let terms = Set(tokenize(query))
        guard !terms.isEmpty else { return [] }

        let scored = sections.enumerated()
            .map { index, section in (index: index, section: section, score: score(section, terms: terms)) }
            .filter { $0.score > 0 }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }

        var keptIndices: Set<Int> = []
        var usedTokens = 0
        for candidate in scored {
            let cost = TokenEstimate.approximate(candidate.section.body)
            if !keptIndices.isEmpty, usedTokens + cost > tokenBudget {
                break
            }
            keptIndices.insert(candidate.index)
            usedTokens += cost
            if usedTokens >= tokenBudget {
                break
            }
        }

        return sections.enumerated()
            .filter { keptIndices.contains($0.offset) }
            .map(\.element)
    }

    private static func score(_ section: SpecSection, terms: Set<String>) -> Int {
        let headingTerms = tokenize(section.headingPath.joined(separator: " "))
        let bodyTerms = tokenize(section.body)
        var total = 0
        for term in headingTerms where terms.contains(term) {
            total += headingWeight
        }
        for term in bodyTerms where terms.contains(term) {
            total += 1
        }
        return total
    }

    /// Lowercased word tokens of length two or more — no stemming and no
    /// synonym expansion, so what matches is what the text actually says.
    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= minimumTermLength }
    }
}
