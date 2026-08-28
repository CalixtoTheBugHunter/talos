@testable import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Verifies ``ContextAssembler`` assembles the right parts and never a
/// secret. Overflow behavior lives in `ContextAssemblerOverflowTests`.
@Suite("Context assembler")
struct ContextAssemblerTests {
    @Test("Assembles the guideline, safeguards, spec drive, connectors, board, and memories")
    func assemblesEveryDeclaredPart() {
        let manifest = ConnectorsManifest(connectors: [
            ConnectorDeclaration(name: "repo", kind: .repo, target: "https://example.com/repo", reachedVia: .cli)
        ])
        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(
                context: ["spec-drive", "connectors", "board", "memories"],
                tokenCeiling: 10000
            ),
            safeguards: makeTestSafeguards(),
            connectors: manifest
        )

        guard case let .assembled(assembled) = makeTestAssembler().assemble(input) else {
            Issue.record("Expected assembly to succeed under a generous ceiling")
            return
        }

        #expect(Set(assembled.includedParts.map(\.kind)) == Set(ContextPartKind.allCases))
    }

    @Test("A part the guideline does not request is never assembled")
    func onlyRequestedPartsAreAssembled() {
        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(context: ["memories"], tokenCeiling: 10000),
            safeguards: makeTestSafeguards(),
            connectors: ConnectorsManifest()
        )

        guard case let .assembled(assembled) = makeTestAssembler().assemble(input) else {
            Issue.record("Expected assembly to succeed")
            return
        }

        #expect(Set(assembled.includedParts.map(\.kind)) == [.guideline, .safeguards, .memories])
    }

    @Test("Assembled connectors text never carries an env value or key")
    func assembledContextNeverCarriesASecret() {
        let manifest = ConnectorsManifest(connectors: [
            ConnectorDeclaration(
                name: "github-repo",
                kind: .repo,
                target: "https://example.com/repo",
                reachedVia: .mcp,
                env: ["GITHUB_TOKEN": .secret(SecretReference(keychainName: "github-pat"))]
            )
        ])
        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(context: ["connectors"], tokenCeiling: 10000),
            safeguards: makeTestSafeguards(),
            connectors: manifest
        )

        guard case let .assembled(assembled) = makeTestAssembler().assemble(input) else {
            Issue.record("Expected assembly to succeed")
            return
        }

        let connectorsText = assembled.includedParts.first { $0.kind == .connectors }?.text ?? ""
        #expect(!connectorsText.contains("GITHUB_TOKEN"))
        #expect(!connectorsText.contains("github-pat"))
    }

    @Test("A source with no content is unavailable, distinct from a part dropped for space")
    func unavailableSourceIsLabeledSeparately() {
        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(context: ["memories"], tokenCeiling: 10000),
            safeguards: makeTestSafeguards(),
            connectors: ConnectorsManifest()
        )
        let memories = FakeContextSource(.unavailable(reason: "no local memories yet"))

        guard case let .assembled(assembled) = makeTestAssembler(memories: memories).assemble(input) else {
            Issue.record("Expected assembly to succeed")
            return
        }

        let expectedUnavailable = UnavailableContextPart(kind: .memories, reason: "no local memories yet")
        #expect(assembled.unavailableParts == [expectedUnavailable])
        #expect(assembled.droppedParts.isEmpty)
        #expect(!assembled.includedParts.contains { $0.kind == .memories })
    }

    @Test("Assembling identical input twice produces an identical result")
    func isDeterministic() {
        func makeInput() -> ContextAssemblyInput {
            ContextAssemblyInput(
                intent: makeTestIntent(),
                guideline: makeTestGuideline(context: ["spec-drive", "memories"], tokenCeiling: 500),
                safeguards: makeTestSafeguards(),
                connectors: ConnectorsManifest()
            )
        }

        let first = makeTestAssembler().assemble(makeInput())
        let second = makeTestAssembler().assemble(makeInput())

        #expect(first == second)
    }

    @Test("Each requested source is fetched at most once per assembly")
    func fetchesEachSourceAtMostOnce() {
        let specDrive = FakeContextSource(.available("Spec drive excerpt."))
        let board = FakeContextSource(.available("Board excerpt."))
        let memories = FakeContextSource(.available("Memories excerpt."))
        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(context: ["spec-drive", "board", "memories"], tokenCeiling: 10000),
            safeguards: makeTestSafeguards(),
            connectors: ConnectorsManifest()
        )

        _ = makeTestAssembler(specDrive: specDrive, board: board, memories: memories).assemble(input)

        #expect(specDrive.fetchCount == 1)
        #expect(board.fetchCount == 1)
        #expect(memories.fetchCount == 1)
    }

    @Test("Talos-added overhead stays under 5% when the user's own prompt carries substantial content")
    func overheadStaysUnderFivePercentForARepresentativeSession() {
        // "Representative" here is a real Automator-style request: the user
        // pastes a stack trace or a file alongside a short instruction, so
        // the raw prompt already carries most of the session's tokens —
        // exactly the case the < 5% budget is meant to hold Talos to.
        let pastedContent = String(repeating: "at com.example.Widget.render(Widget.java:42)\n", count: 200)
        let input = ContextAssemblyInput(
            intent: makeTestIntent(content: "Here is the crash log, please fix it:\n\(pastedContent)"),
            guideline: makeTestGuideline(
                context: ["connectors"],
                tokenCeiling: 4000,
                rawText: "Carry out a requested change under the Safeguards gate."
            ),
            safeguards: makeTestSafeguards(rawText: "Never deploy on a Friday. Always run tests first."),
            connectors: ConnectorsManifest(connectors: [
                ConnectorDeclaration(name: "repo", kind: .repo, target: "https://example.com/repo", reachedVia: .cli)
            ])
        )

        guard case let .assembled(assembled) = makeTestAssembler().assemble(input) else {
            Issue.record("Expected assembly to succeed")
            return
        }

        #expect(assembled.overheadRatio < 0.05)
    }
}
