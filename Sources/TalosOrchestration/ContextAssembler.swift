import TalosProjectLibrary

/// What ``ContextAssembler/assemble(_:)`` needs to assemble one session's
/// context. `guideline` must be the caller's own guideline for
/// `intent.requestingSubFunction` — this type does not re-derive or check
/// that correspondence.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public struct ContextAssemblyInput: Sendable {
    public let intent: Intent
    public let guideline: GuidelineDocument
    public let safeguards: SafeguardsDocument
    public let connectors: ConnectorsManifest

    public init(
        intent: Intent,
        guideline: GuidelineDocument,
        safeguards: SafeguardsDocument,
        connectors: ConnectorsManifest
    ) {
        self.intent = intent
        self.guideline = guideline
        self.safeguards = safeguards
        self.connectors = connectors
    }
}

/// One context part that made it into the assembled session, with the text
/// exactly as assembled and its estimated size.
public struct IncludedContextPart: Equatable, Sendable {
    public let kind: ContextPartKind
    public let text: String
    public let estimatedTokens: Int
}

/// One droppable part removed to satisfy the ceiling. Removed whole, never
/// truncated — this struct carries no partial text because none exists.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling
public struct DroppedContextPart: Equatable, Sendable {
    public let kind: ContextPartKind
    public let estimatedTokens: Int
    public let reason: String
}

/// One requested part that had no content to assemble at all — distinct
/// from a part dropped for space. See ``ContextFragment``.
public struct UnavailableContextPart: Equatable, Sendable {
    public let kind: ContextPartKind
    public let reason: String
}

/// One pinned part's size and the file that declares it, named in a
/// ``ContextAssemblyFailure`` so the user sees both remedies: raise the
/// ceiling in that file, or shorten the other one.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-the-pinned-parts-alone-exceed-the-ceiling
public struct PinnedPartCost: Equatable, Sendable {
    public let kind: ContextPartKind
    public let estimatedTokens: Int
    public let file: String
}

/// The pinned parts alone exceed the guideline's declared ceiling, so no
/// dropping can satisfy it and the session does not start. This is
/// **Failed**, not **Denied** — nothing was gated and the user refused
/// nothing.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-the-pinned-parts-alone-exceed-the-ceiling
public struct ContextAssemblyFailure: Equatable, Sendable {
    public let ceiling: Int
    public let pinnedCosts: [PinnedPartCost]
}

/// One session's assembled context. `overheadRatio` is Talos-added token
/// overhead — "the context Talos injects ... versus the tokens the agent
/// would have used from the raw user prompt" — with both sides measured by
/// the same ``TokenEstimate``, so the ratio is reproducible even though
/// neither side alone is exact. Reconciling this against the agent's own
/// accurate post-session token report, and recording it for the Monitor
/// Screen, is the consuming caller's job (tracked separately — the Monitor
/// Screen itself does not exist yet).
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
public struct AssembledContext: Equatable, Sendable {
    public let includedParts: [IncludedContextPart]
    public let droppedParts: [DroppedContextPart]
    public let unavailableParts: [UnavailableContextPart]
    public let assembledTokens: Int
    public let rawPromptTokenEstimate: Int

    /// Includes ``PromptDataFraming/overheadTokens(for:)`` — the framing
    /// added when this context reaches the prompt — since that is real
    /// Talos-added overhead. `assembledTokens` itself stays framing-free: it
    /// is what the guideline's declared ceiling is checked against, and the
    /// ceiling governs content, not the fixed cost of the safety wrapper.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture
    public var overheadRatio: Double {
        let overhead = assembledTokens + PromptDataFraming.overheadTokens(for: includedParts)
        let total = overhead + rawPromptTokenEstimate
        guard total > 0 else { return 0 }
        return Double(overhead) / Double(total)
    }
}

/// What one call to ``ContextAssembler/assemble(_:)`` produced.
public enum ContextAssemblyResult: Equatable, Sendable {
    case assembled(AssembledContext)
    case failed(ContextAssemblyFailure)
}

/// Assembles one session's prompt context from the Project Library, within
/// the requesting sub-function's declared token ceiling. Pure and
/// deterministic: the same input always produces the same result, which is
/// what keeps the overhead this type measures reproducible.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling
public struct ContextAssembler: Sendable {
    private let specDriveSource: SpecDriveContextSource
    private let boardSource: BoardStateContextSource
    private let memoriesSource: MemoriesContextSource

    public init(
        specDriveSource: SpecDriveContextSource,
        boardSource: BoardStateContextSource,
        memoriesSource: MemoriesContextSource
    ) {
        self.specDriveSource = specDriveSource
        self.boardSource = boardSource
        self.memoriesSource = memoriesSource
    }

    /// The `.talos/` paths a ``ContextAssemblyFailure`` names.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
    private static let guidelinesDirectory = ".talos/guidelines/"
    private static let safeguardsFile = ".talos/safeguards.md"

    public func assemble(_ input: ContextAssemblyInput) -> ContextAssemblyResult {
        let guidelineTokens = TokenEstimate.approximate(input.guideline.rawText)
        let safeguardsTokens = TokenEstimate.approximate(input.safeguards.rawText)
        let ceiling = input.guideline.tokenCeiling

        guard guidelineTokens + safeguardsTokens <= ceiling else {
            return .failed(pinnedOverflow(
                guidelineTokens: guidelineTokens,
                safeguardsTokens: safeguardsTokens,
                ceiling: ceiling,
                input: input
            ))
        }

        let gathered = gatherDroppableParts(input)
        var runningTotal = guidelineTokens + safeguardsTokens + gathered.tokenTotal
        var remaining = gathered.included
        let dropped = dropUntilUnderCeiling(&remaining, runningTotal: &runningTotal, ceiling: ceiling, input: input)

        let included = [
            IncludedContextPart(kind: .guideline, text: input.guideline.rawText, estimatedTokens: guidelineTokens),
            IncludedContextPart(kind: .safeguards, text: input.safeguards.rawText, estimatedTokens: safeguardsTokens)
        ] + remaining

        return .assembled(AssembledContext(
            includedParts: included,
            droppedParts: dropped,
            unavailableParts: gathered.unavailable,
            assembledTokens: runningTotal,
            rawPromptTokenEstimate: TokenEstimate.approximate(input.intent.content)
        ))
    }

    private func pinnedOverflow(
        guidelineTokens: Int,
        safeguardsTokens: Int,
        ceiling: Int,
        input: ContextAssemblyInput
    ) -> ContextAssemblyFailure {
        let guidelineFile = Self.guidelinesDirectory + input.guideline.subFunction.guidelineFileName
        return ContextAssemblyFailure(
            ceiling: ceiling,
            pinnedCosts: [
                PinnedPartCost(kind: .guideline, estimatedTokens: guidelineTokens, file: guidelineFile),
                PinnedPartCost(kind: .safeguards, estimatedTokens: safeguardsTokens, file: Self.safeguardsFile)
            ]
        )
    }

    private struct GatheredDroppableParts {
        let included: [IncludedContextPart]
        let unavailable: [UnavailableContextPart]
        let tokenTotal: Int
    }

    /// Fetches every droppable part the guideline's own `context` list
    /// requests, in ``ContextPartKind``'s declared order — never the
    /// guideline's — so assembly is deterministic regardless of how the
    /// guideline lists them.
    private func gatherDroppableParts(_ input: ContextAssemblyInput) -> GatheredDroppableParts {
        let requestedKinds = Set(input.guideline.context.compactMap(ContextPartKind.init(rawValue:)))
            .filter { !$0.isPinned }

        var included: [IncludedContextPart] = []
        var unavailable: [UnavailableContextPart] = []
        var total = 0

        for kind in ContextPartKind.allCases where requestedKinds.contains(kind) {
            switch fetchFragment(kind: kind, input: input) {
            case let .available(text):
                let tokens = TokenEstimate.approximate(text)
                included.append(IncludedContextPart(kind: kind, text: text, estimatedTokens: tokens))
                total += tokens
            case let .unavailable(reason):
                unavailable.append(UnavailableContextPart(kind: kind, reason: reason))
            }
        }

        return GatheredDroppableParts(included: included, unavailable: unavailable, tokenTotal: total)
    }

    /// Drops whole parts, in ``ContextPartKind/dropOrder``, until
    /// `runningTotal` fits `ceiling` or nothing droppable remains. Never
    /// truncates — a part is removed entirely or not at all.
    private func dropUntilUnderCeiling(
        _ remaining: inout [IncludedContextPart],
        runningTotal: inout Int,
        ceiling: Int,
        input: ContextAssemblyInput
    ) -> [DroppedContextPart] {
        var dropped: [DroppedContextPart] = []
        for kind in ContextPartKind.dropOrder {
            guard runningTotal > ceiling else { break }
            guard let index = remaining.firstIndex(where: { $0.kind == kind }) else { continue }
            let part = remaining.remove(at: index)
            runningTotal -= part.estimatedTokens
            dropped.append(DroppedContextPart(
                kind: kind,
                estimatedTokens: part.estimatedTokens,
                reason: dropReason(subFunction: input.guideline.subFunction, ceiling: ceiling)
            ))
        }
        return dropped
    }

    private func dropReason(subFunction: SubFunction, ceiling: Int) -> String {
        "dropped to satisfy the \(subFunction.rawValue) guideline's \(ceiling)-token ceiling"
    }

    /// Fetches one droppable part's content. Never called with a pinned
    /// kind — the caller filters those out before this runs.
    private func fetchFragment(kind: ContextPartKind, input: ContextAssemblyInput) -> ContextFragment {
        switch kind {
        case .specDrive:
            specDriveSource.fetch(for: input.intent)
        case .board:
            boardSource.fetch(for: input.intent)
        case .memories:
            memoriesSource.fetch(for: input.intent)
        case .connectors:
            .available(ConnectorsContextRendering.render(input.connectors))
        case .guideline, .safeguards:
            preconditionFailure("ContextAssembler never fetches a pinned kind as droppable content")
        }
    }
}
