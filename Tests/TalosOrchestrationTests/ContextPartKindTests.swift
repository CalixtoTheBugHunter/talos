import TalosOrchestration
import Testing

/// Verifies ``ContextPartKind`` is the exact, whole set of assembled
/// context parts — the same discipline `BoardState`'s "six states, whole
/// set" test uses, so an added case is caught here rather than downstream.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
@Suite("Context part kind")
struct ContextPartKindTests {
    @Test("Exactly six parts exist, and Root Talos Guidelines is not one of them")
    func wholeSetIsSixParts() {
        #expect(ContextPartKind.allCases.count == 6)
        #expect(Set(ContextPartKind.allCases) == [.guideline, .safeguards, .specDrive, .connectors, .board, .memories])
    }

    @Test("Only the guideline and Safeguards are pinned")
    func onlyGuidelineAndSafeguardsArePinned() {
        for kind in ContextPartKind.allCases {
            let expected = kind == .guideline || kind == .safeguards
            #expect(kind.isPinned == expected)
        }
    }

    @Test("The compiled-in default drop order is memories, board, connectors, spec-drive")
    func defaultDropOrderMatchesDecision47() {
        #expect(ContextPartKind.dropOrder == [.memories, .board, .connectors, .specDrive])
    }

    @Test("Droppable raw values match the identifiers a guideline's own context list uses")
    func rawValuesMatchGuidelineContextIdentifiers() {
        #expect(ContextPartKind.specDrive.rawValue == "spec-drive")
        #expect(ContextPartKind.connectors.rawValue == "connectors")
        #expect(ContextPartKind.board.rawValue == "board")
        #expect(ContextPartKind.memories.rawValue == "memories")
    }
}
