import TalosOrchestration
import Testing

/// Verifies ``TokenEstimate`` is a pure, deterministic size approximation —
/// never a model call — per
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary.
@Suite("Token estimate")
struct TokenEstimateTests {
    @Test("An empty string estimates to zero tokens")
    func emptyStringIsZero() {
        #expect(TokenEstimate.approximate("") == 0)
    }

    @Test("A non-empty string never estimates to zero")
    func shortNonEmptyStringIsNeverZero() {
        #expect(TokenEstimate.approximate("a") > 0)
    }

    @Test("Estimating the same text twice returns the same value")
    func isDeterministic() {
        let text = "Carry out a requested change under the Safeguards gate."
        let first = TokenEstimate.approximate(text)
        let second = TokenEstimate.approximate(text)
        #expect(first == second)
    }

    @Test("Longer text estimates to more tokens")
    func longerTextEstimatesHigher() {
        let short = "Short prompt."
        let long = String(repeating: "Longer prompt with much more text in it. ", count: 50)
        #expect(TokenEstimate.approximate(long) > TokenEstimate.approximate(short))
    }
}
