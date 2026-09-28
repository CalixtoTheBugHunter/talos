import Foundation
import TalosAdapters
@testable import TalosOrchestration
import Testing

/// Cost is an estimate mapped from the agent's token counts against price
/// tables shipped with the app — per model, offline, and never guessed for a
/// model the table does not price.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
@Suite("Price table")
struct PriceTableTests {
    /// Rates chosen so a million tokens on each axis costs the axis's rate
    /// exactly — the estimate is the sum of the four rates, and each axis is
    /// priced on its own (a cache read far below a fresh input token).
    private static let table = PriceTable(
        effectiveDate: Date(timeIntervalSince1970: 0),
        prices: [
            "claude-opus-5": ModelPrice(
                inputPerMillion: 10, outputPerMillion: 20,
                cacheWritePerMillion: 30, cacheReadPerMillion: 5
            )
        ]
    )

    @Test("Cost sums all four token axes at their own rate")
    func costSumsAllFourAxes() {
        let counts = TokenCounts(input: 1_000_000, output: 1_000_000, cacheCreation: 1_000_000, cacheRead: 1_000_000)
        let estimate = Self.table.estimate(for: .measured(counts, model: "claude-opus-5"))
        #expect(estimate == .estimated(10 + 20 + 30 + 5))
    }

    @Test("An absent cache axis contributes nothing, never a guessed cost")
    func absentCacheAxisContributesNothing() {
        let counts = TokenCounts(input: 1_000_000, output: 0)
        let estimate = Self.table.estimate(for: .measured(counts, model: "claude-opus-5"))
        #expect(estimate == .estimated(10))
    }

    /// "An unknown model reports tokens with cost marked unavailable, never
    /// guessed." The tokens stay known; only the cost is absent and named.
    @Test("An unknown model yields unavailable, never a guessed or zero cost")
    func unknownModelYieldsUnavailable() {
        let counts = TokenCounts(input: 100, output: 100)
        let estimate = Self.table.estimate(for: .measured(counts, model: "some-unlisted-model"))
        #expect(estimate == .unavailable(.unknownModel("some-unlisted-model")))
    }

    @Test("An unavailable token report makes the cost unavailable too")
    func unavailableTokensMakeCostUnavailable() {
        let report = TokenReport.unavailable(TokenUsageUnavailable(reason: .unrecognizedFormat))
        #expect(Self.table.estimate(for: report) == .unavailable(.tokensUnavailable(.unrecognizedFormat)))
    }

    /// The recorded model name may carry a provider/region prefix; the table
    /// keys on the model, so the prefixed and bare forms price identically.
    /// Matching is exact after the prefix — no fuzzy fallback to a price.
    @Test("A provider-prefixed model name resolves to the same price")
    func providerPrefixResolves() {
        let counts = TokenCounts(input: 1_000_000, output: 0)
        let prefixed = Self.table.estimate(for: .measured(counts, model: "global.anthropic.claude-opus-5"))
        #expect(prefixed == .estimated(10))
    }

    /// AC4: pricing needs no network. Offline is structural — the shipped table
    /// is a compiled-in constant and `estimate` is a pure function, reached here
    /// with no `await` and no I/O, so no network is in the call path. Asserting
    /// the exact estimate also guards the computation and the derived cache
    /// rates (write 1.25×, read 0.1× input) against a silent regression.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#no-telemetry
    @Test("Pricing is offline and prices a known model to its exact estimate")
    func pricingIsOffline() {
        let counts = TokenCounts(input: 2, output: 4, cacheCreation: 2637, cacheRead: 16509)
        let estimate = PriceTable.shipped.estimate(for: .measured(counts, model: "global.anthropic.claude-opus-5"))
        // 2·15 + 4·75 + 2637·18.75 + 16509·1.5, all ÷ 1_000_000 = 0.07453725 USD.
        #expect(estimate == .estimated(Decimal(sign: .plus, exponent: -8, significand: 7_453_725)))
    }

    /// AC6: the shipped table carries the date its prices were set, so the UI
    /// can show how current the estimate's basis is.
    @Test("The shipped table has an effective date")
    func shippedTableHasEffectiveDate() {
        #expect(PriceTable.shipped.effectiveDate > Date(timeIntervalSince1970: 0))
    }
}
