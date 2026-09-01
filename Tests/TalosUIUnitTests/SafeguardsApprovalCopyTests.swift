import TalosCore
import TalosSafeguards
import TalosUI
import Testing

private let writeTierActions: [SafeguardsActionType] = [
    .fileWrite, .fileMove, .gitCommit, .gitBranchCreate, .gitPush, .gitPROpen, .gitPRComment,
    .boardItemCreate, .boardItemMove, .boardItemUpdate, .boardItemComment, .specWrite,
    .configWrite, .configGuidelinesWrite, .connectorWrite
]

private let irreversibleTierActions: [SafeguardsActionType] = [
    .processRun, .fileDelete, .gitPushProtected, .gitPushForce, .gitHistoryRewrite,
    .gitBranchDelete, .gitRepoDelete, .gitPRMerge, .boardItemDelete, .specDelete,
    .specDriveCreate, .secretRead, .secretWrite, .secretSend, .deployStaging,
    .deployProduction, .packageInstall, .packagePublish, .spendPaid, .connectorUndeclared
]

/// Every action type the gate can ever prompt for — read and refused types
/// never reach a prompt — has a label naming the action rather than falling
/// back to the honest-but-generic default.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
@Suite("Safeguards approval copy: every known action type has a specific label")
struct SafeguardsApprovalCopyKnownActionTests {
    @Test("Write tier", arguments: writeTierActions)
    func writeTierHasASpecificLabel(action: SafeguardsActionType) {
        let label = SafeguardsApprovalCopy.operationLabel(for: action)
        #expect(!label.isEmpty)
        #expect(label != "Approve this action")
    }

    @Test("Irreversible tier", arguments: irreversibleTierActions)
    func irreversibleTierHasASpecificLabel(action: SafeguardsActionType) {
        let label = SafeguardsApprovalCopy.operationLabel(for: action)
        #expect(!label.isEmpty)
        #expect(label != "Approve this action")
    }
}

@Suite("Safeguards approval copy: unrecognized action falls back honestly")
struct SafeguardsApprovalCopyFallbackTests {
    @Test("An action type outside the taxonomy gets the honest fallback, not an invented specific")
    func unrecognizedActionFallsBack() {
        let label = SafeguardsApprovalCopy.operationLabel(for: SafeguardsActionType(rawValue: "not.a.real.action"))
        #expect(label == "Approve this action")
    }
}

/// Reversibility is a property of the tier, not of the individual action —
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers
/// names the write tier as ordinary mutation and the irreversible tier as
/// exactly that.
@Suite("Safeguards approval copy: reversibility follows the tier")
struct SafeguardsApprovalCopyReversibilityTests {
    @Test("Write tier states it can be undone")
    func writeTierCanBeUndone() {
        #expect(SafeguardsApprovalCopy.reversibilityStatement(for: .write) == "This can be undone.")
    }

    @Test("Irreversible tier states it cannot be undone")
    func irreversibleTierCannotBeUndone() {
        #expect(SafeguardsApprovalCopy.reversibilityStatement(for: .irreversible) == "This cannot be undone.")
    }
}
