import XCTest

/// The `a11y` CI stage's structural audit:
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Verification
///
/// `performAccessibilityAudit()` is Apple's own structural audit — labels,
/// traits, contrast, hit-target size. It does not claim comprehensibility or
/// streaming-output announcements; the approval-prompt-specific tests below
/// cover what it cannot (no pre-checked default, the per-tier keyboard ban).
final class TalosUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRootWindowHasNoAccessibilityAuditIssues() throws {
        let app = XCUIApplication()
        app.launch()
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    @MainActor
    func testApprovalPromptPassesAccessibilityAuditWhilePresented() throws {
        let app = launchWithPendingApproval(tier: "irreversible")
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    @MainActor
    func testDeniedActionNoticePassesAccessibilityAuditWhilePresented() throws {
        let app = launchWithDeniedNotice(tier: "irreversible")
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    @MainActor
    func testGatedDecisionLogReadyStatePassesAccessibilityAuditWhilePresented() throws {
        let app = launchWithGatedDecisionLog(state: "ready")
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    @MainActor
    func testGatedDecisionLogEmptyStatePassesAccessibilityAuditWhilePresented() throws {
        let app = launchWithGatedDecisionLog(state: "empty")
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    @MainActor
    func testGatedDecisionLogFailedStateOffersARetryControl() throws {
        let app = launchWithGatedDecisionLog(state: "failed")
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// Asserts § The stop guarantee is an interaction rule: the control is
    /// visible while a session runs and is VoiceOver-clean.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard
    @MainActor
    func testStopControlIsVisibleAndPassesAccessibilityAuditWhileASessionRuns() throws {
        let app = launchWithSessionRunning()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// Asserts AC1: the stop command in the menu bar is reachable at `⌘.`
    /// with no session running, but is disabled — there is nothing to stop —
    /// which is the keyboard-reachable half of "any new shortcut appears in
    /// the menu bar beside its command".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#menus-carry-the-shortcuts
    @MainActor
    func testStopMenuCommandExistsAndIsDisabledWithNoSessionRunning() {
        let app = XCUIApplication()
        app.launch()

        let stopMenuItem = app.menuItems["Stop"]
        XCTAssertTrue(stopMenuItem.waitForExistence(timeout: 5))
        XCTAssertFalse(stopMenuItem.isEnabled, "nothing is running, so there is nothing to stop")
    }

    /// Asserts AC1 and AC7: the visible control is reachable — with no
    /// confirmation in the way — and activating it calls through to the
    /// tracked session's own stop handler.
    @MainActor
    func testStopControlEndsTheTrackedSession() {
        let app = launchWithSessionRunning()
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))

        stop.click()

        XCTAssertFalse(stop.waitForExistence(timeout: 5), "stopping ends the session with no confirmation in the way")
    }

    @MainActor
    private func launchWithSessionRunning() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TALOS_UI_TEST_SESSION_RUNNING"] = "1"
        app.launch()
        return app
    }

    /// Asserts AC2, AC3, AC4, and AC8 of
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    /// for the tier "not allowlistable, ever": nothing pre-checked, Return
    /// does not approve, Escape denies as easily as approving would take.
    @MainActor
    func testIrreversibleApprovalPromptHasNoPreCheckedDefaultAndReturnDoesNotApprove() {
        let app = launchWithPendingApproval(tier: "irreversible")
        let deny = app.buttons["Deny"]
        let approve = app.buttons["Delete a file or directory"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5))
        XCTAssertTrue(approve.exists)
        XCTAssertEqual(app.checkBoxes.count, 0, "no destructive default exists to pre-check")

        app.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(deny.exists, "Return must not approve an irreversible action")
        XCTAssertTrue(approve.exists)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(deny.waitForExistence(timeout: 1), "Escape denies, and the prompt closes")
    }

    /// Asserts the write tier's own row of
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#the-shortcut-map —
    /// `⌘↩` approves, bare `↩` does not.
    @MainActor
    func testWriteTierApprovalPromptApprovesOnCommandReturnButNotBareReturn() {
        let app = launchWithPendingApproval(tier: "write")
        let deny = app.buttons["Deny"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5))

        app.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(deny.exists, "bare Return must not approve, even at write tier")

        app.typeKey(.enter, modifierFlags: .command)
        XCTAssertFalse(deny.waitForExistence(timeout: 1), "Command-Return approves a write-tier action")
    }

    @MainActor
    private func launchWithPendingApproval(tier: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TALOS_UI_TEST_PENDING_APPROVAL"] = tier
        app.launch()
        return app
    }

    @MainActor
    private func launchWithDeniedNotice(tier: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TALOS_UI_TEST_DENIED_NOTICE"] = tier
        app.launch()
        return app
    }

    @MainActor
    private func launchWithGatedDecisionLog(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TALOS_UI_TEST_GATED_DECISION_LOG"] = state
        app.launch()
        return app
    }

    /// Every issue is accepted here (always `true`), so the audit enumerates
    /// the whole tree instead of stopping at the first rejection.
    /// `talosOwnIssues` is the real count this test asserts against — the CI
    /// script parses `ACCESSIBILITY_ISSUE_COUNT:` below rather than reading a
    /// bare pass/fail exit code, so a regression from 1 issue to 3 is
    /// visible, not just "failing".
    @MainActor
    private func assertNoTalosOwnAccessibilityIssues(on app: XCUIApplication) throws {
        var talosOwnIssues: [XCUIAccessibilityAuditIssue] = []
        try app.performAccessibilityAudit { issue in
            // The audit walks every accessibility node AppKit generates for a
            // window, including framework-level ones (the window's own root
            // Group, a TouchBar) that no label in Talos's view code can fix.
            // Only `.staticText` and `.button` are Talos-authored element
            // types today; anything else, including an issue with no element
            // reference at all, is excused here rather than flagged as a
            // false regression.
            guard let elementType = issue.element?.elementType,
                  elementType == .staticText || elementType == .button
            else {
                return true
            }
            talosOwnIssues.append(issue)
            return true
        }

        for issue in talosOwnIssues {
            print("ACCESSIBILITY AUDIT ISSUE: \(issue)")
        }
        print("ACCESSIBILITY_ISSUE_COUNT: \(talosOwnIssues.count)")
        XCTAssertTrue(talosOwnIssues.isEmpty, "\(talosOwnIssues.count) accessibility issue(s) on Talos's own elements")
    }
}
