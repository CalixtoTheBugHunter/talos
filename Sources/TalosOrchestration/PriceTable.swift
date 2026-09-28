import Foundation
import TalosAdapters

/// A model's public list price, per million tokens of each kind. Four rates,
/// not one: a cache read is priced far below a fresh input token and a cache
/// write above it, so folding them together would make the estimate wrong.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
public struct ModelPrice: Equatable, Sendable {
    public let inputPerMillion: Decimal
    public let outputPerMillion: Decimal
    public let cacheWritePerMillion: Decimal
    public let cacheReadPerMillion: Decimal

    public init(
        inputPerMillion: Decimal,
        outputPerMillion: Decimal,
        cacheWritePerMillion: Decimal,
        cacheReadPerMillion: Decimal
    ) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheWritePerMillion = cacheWritePerMillion
        self.cacheReadPerMillion = cacheReadPerMillion
    }

    /// Derives the cache rates from the public Anthropic structure: a cache
    /// write is 1.25× a fresh input token and a cache read 0.1×. Used by the
    /// shipped table so each model states only its input and output rates.
    public init(inputPerMillion: Decimal, outputPerMillion: Decimal) {
        self.init(
            inputPerMillion: inputPerMillion,
            outputPerMillion: outputPerMillion,
            cacheWritePerMillion: inputPerMillion * Self.cacheWriteMultiplier,
            cacheReadPerMillion: inputPerMillion * Self.cacheReadMultiplier
        )
    }

    private static let cacheWriteMultiplier: Decimal = 1.25
    private static let cacheReadMultiplier: Decimal = 0.1
}

/// Why a cost estimate could not be produced — named, never a guessed number
/// and never `$0`, on the same terms the token count itself uses for absence.
public enum CostUnavailableReason: Equatable, Sendable {
    /// The model the agent reported has no row in the shipped table. The tokens
    /// are still known; the cost is not, and is not inferred from a neighbour.
    case unknownModel(String)
    /// The token counts were themselves unavailable, so nothing derived from
    /// them exists to price.
    case tokensUnavailable(TokenUsageUnavailableReason)
}

/// A run's cost, always an estimate. Two cases rather than a number with a
/// failure flag, so an absent cost cannot be spelled as `0`: the SPEC forbids
/// showing an absence as a measured figure.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
public enum CostEstimate: Equatable, Sendable {
    case estimated(Decimal)
    case unavailable(CostUnavailableReason)
}

/// Public price tables shipped inside the app as data and mapped against the
/// token counts the agent reported. There is no network call: the table is
/// compiled in and updated by a release, and the model name selecting a row
/// comes from the agent's own report — never inferred.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#no-telemetry
public struct PriceTable: Equatable, Sendable {
    /// The date these prices were last set, surfaced so the user can judge how
    /// current the estimate's basis is.
    public let effectiveDate: Date
    private let prices: [String: ModelPrice]

    public init(effectiveDate: Date, prices: [String: ModelPrice]) {
        self.effectiveDate = effectiveDate
        self.prices = prices
    }

    /// The estimate for one run's usage. A model with no row yields
    /// `.unavailable(.unknownModel)`; an unavailable token report propagates as
    /// `.unavailable(.tokensUnavailable)`. Pure and synchronous — no I/O, so no
    /// network is reachable from pricing.
    public func estimate(for report: TokenReport) -> CostEstimate {
        switch report {
        case let .measured(counts, model):
            guard let price = price(for: model) else {
                return .unavailable(.unknownModel(model))
            }
            return .estimated(Self.cost(of: counts, at: price))
        case let .unavailable(unavailable):
            return .unavailable(.tokensUnavailable(unavailable.reason))
        }
    }

    private func price(for model: String) -> ModelPrice? {
        prices[model] ?? prices[Self.normalized(model)]
    }

    /// Strips a leading provider/region prefix an agent may prepend to the
    /// model name (`global.anthropic.claude-opus-5` → `claude-opus-5`), so the
    /// table keys on the model rather than on where it ran. Exact after that:
    /// an unrecognized name is unknown, never fuzzily matched to a price.
    static func normalized(_ model: String) -> String {
        for prefix in ["global.anthropic.", "anthropic."] where model.hasPrefix(prefix) {
            return String(model.dropFirst(prefix.count))
        }
        return model
    }

    /// A nil cache axis contributes nothing: the agent named no cache usage, so
    /// there is no cache cost to add — an absence, not a measured zero.
    static func cost(of counts: TokenCounts, at price: ModelPrice) -> Decimal {
        let million: Decimal = 1_000_000
        let input = Decimal(counts.input) * price.inputPerMillion
        let output = Decimal(counts.output) * price.outputPerMillion
        let cacheWrite = Decimal(counts.cacheCreation ?? 0) * price.cacheWritePerMillion
        let cacheRead = Decimal(counts.cacheRead ?? 0) * price.cacheReadPerMillion
        return (input + output + cacheWrite + cacheRead) / million
    }
}

public extension PriceTable {
    /// The table shipped with this build. Rates are Anthropic public list
    /// prices per million tokens as of ``effectiveDate``, seeded from the
    /// public structure (cache write 1.25× input, cache read 0.1× input) and
    /// updated per release — VERIFY the rates and the effective date against
    /// Anthropic's published pricing before shipping a release.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
    static let shipped = PriceTable(
        effectiveDate: shippedEffectiveDate,
        prices: [
            "claude-opus-5": opus,
            "claude-opus-5-5": opus,
            "claude-sonnet-5": sonnet,
            "claude-haiku-4-5": haiku
        ]
    )

    // Input and output rates, USD per million tokens; cache rates are derived
    // from the public structure by ``ModelPrice/init(inputPerMillion:outputPerMillion:)``.
    private static let opusInputRate: Decimal = 15
    private static let opusOutputRate: Decimal = 75
    private static let sonnetInputRate: Decimal = 3
    private static let sonnetOutputRate: Decimal = 15
    private static let haikuInputRate: Decimal = 0.8
    private static let haikuOutputRate: Decimal = 4

    private static let opus = ModelPrice(inputPerMillion: opusInputRate, outputPerMillion: opusOutputRate)
    private static let sonnet = ModelPrice(inputPerMillion: sonnetInputRate, outputPerMillion: sonnetOutputRate)
    private static let haiku = ModelPrice(inputPerMillion: haikuInputRate, outputPerMillion: haikuOutputRate)

    private static let shippedEffectiveDate: Date = {
        let year = 2026
        let month = 9
        let day = 28
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()
}
