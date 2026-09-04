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
        XCTAssertTrue(app.buttons["Stop session"].waitForExistence(timeout: 5))
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

        let stopMenuItem = app.menuItems["Stop session"]
        XCTAssertTrue(stopMenuItem.waitForExistence(timeout: 5))
        XCTAssertFalse(stopMenuItem.isEnabled, "nothing is running, so there is nothing to stop")
    }

    /// Asserts AC1 and AC7: the visible control is reachable — with no
    /// confirmation in the way — and activating it calls through to the
    /// tracked session's own stop handler.
    @MainActor
    func testStopControlEndsTheTrackedSession() {
        let app = launchWithSessionRunning()
        let stop = app.buttons["Stop session"]
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

    /// Asserts AC5 and the structural half of AC7 of
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is —
    /// the seeded transcript's own rows carry real labels and roles.
    @MainActor
    func testSessionConsoleTranscriptPassesAccessibilityAuditWhilePresented() throws {
        let app = launchWithSessionConsoleTranscript()
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// Asserts AC6's "follows new output" half through the real, mounted
    /// view: the seeded transcript's last line is visible with no manual
    /// scrolling, which only holds if the view auto-scrolled past the
    /// seeded 120k-character line ahead of it.
    @MainActor
    func testSessionConsoleTranscriptScrollsToLatestOutputByDefault() {
        let app = launchWithSessionConsoleTranscript()
        XCTAssertTrue(
            app.staticTexts["Done."].waitForExistence(timeout: 5),
            "the transcript follows new output to the bottom by default"
        )
    }

    /// Asserts ``SessionConsoleViewModel/State/loading``: the surface shows
    /// activity plus the current step in words before the agent's first token.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback
    @MainActor
    func testSessionConsoleLoadingStatePassesAccessibilityAuditWhilePresented() throws {
        let app = launchWithSessionConsoleTranscript(state: "loading")
        XCTAssertTrue(app.staticTexts["Waiting for the agent to respond."].waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// Asserts ``SessionConsoleViewModel/State/failed(_:)``: a non-zero exit
    /// is attributed to the agent, over the transcript it already produced —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors.
    @MainActor
    func testSessionConsoleFailedStateShowsTheStatusBannerOverTheTranscript() throws {
        let app = launchWithSessionConsoleTranscript(state: "failed")
        XCTAssertTrue(app.staticTexts["Found 3 matches."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Exited with status 1. Output above."].waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// Asserts ``SessionConsoleViewModel/State/denied(_:)``: neutral copy,
    /// never an error treatment —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure.
    @MainActor
    func testSessionConsoleDeniedStateShowsTheStatusBanner() throws {
        let app = launchWithSessionConsoleTranscript(state: "denied")
        XCTAssertTrue(app.staticTexts["Denied. Session ended, nothing further ran."].waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// Token usage is stated plainly, and the Talos-added overhead is a
    /// distinct, named figure rather than folded into the agent's own count.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    @MainActor
    func testSessionConsoleShowsLiveTokenUsageWithOverheadDistinguished() throws {
        let app = launchWithSessionConsoleTranscript(state: "token-usage")
        XCTAssertTrue(
            app.staticTexts["1200 input · 340 output tokens (claude-opus-5) — about 12% Talos-added token overhead"]
                .waitForExistence(timeout: 5)
        )
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// A token count Talos could not measure reads "Unavailable", never a
    /// zero.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
    @MainActor
    func testSessionConsoleShowsTokenUsageUnavailableRatherThanZero() throws {
        let app = launchWithSessionConsoleTranscript(state: "token-usage-unavailable")
        XCTAssertTrue(app.staticTexts["Token usage unavailable — not yet reported"].waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    @MainActor
    private func launchWithSessionConsoleTranscript(state: String = "1") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TALOS_UI_TEST_SESSION_CONSOLE_TRANSCRIPT"] = state
        app.launch()
        return app
    }

    /// Asserts AC1 and AC6 of
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is —
    /// a read-tier call renders as a distinct, scannable element naming its
    /// target, and is a real accessibility element rather than one that
    /// "never prompts" also meaning "never announced".
    @MainActor
    func testSessionConsoleReadTierToolCallIsVisibleAndPassesAccessibilityAudit() throws {
        let app = launchWithSessionConsoleTranscript(state: "tool-call-read")
        XCTAssertTrue(
            app.staticTexts["Read Sources/Talos/Legacy/Old.swift"].waitForExistence(timeout: 5),
            "the tool and its target are both named, not just the tool"
        )
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// Asserts AC3 of
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is —
    /// the pending approval is reachable inside the console's own window,
    /// never a second, detached window the way `.sheet` presents one. Also
    /// asserts AC2: the tier is visible, so the user can see why it prompted.
    @MainActor
    func testSessionConsolePendingApprovalIsInlineNotADetachedWindow() {
        let app = launchWithSessionConsoleTranscript(state: "tool-call-pending-write")
        let deny = app.buttons["Deny"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5))

        // The console itself is always hosted in its own sheet (see
        // `seedSessionConsoleTranscriptForUITestingIfRequested`), so `1` here
        // is that sheet alone — a second, detached approval sheet stacked on
        // top of it would make this `2`.
        XCTAssertEqual(app.sheets.count, 1, "the approval is a row in the transcript, never a second, detached sheet")
        XCTAssertTrue(
            app.staticTexts["The agent wants to modify Sources/Talos/Legacy/Old.swift."].exists,
            "the sentence naming the operation and target is visible, not hidden behind a disclosure"
        )
        XCTAssertTrue(
            app.staticTexts["Write · This can be undone."].exists,
            "the tier is visible, not only inferable from the reversibility statement alone"
        )
    }

    /// Asserts AC5 for the approved outcome: resolving inline leaves the row
    /// visible with its outcome rather than dismissing it — the same
    /// "denied and approved calls remain visible" line, exercised on the
    /// side that is easy to mistake for "done, so it can disappear".
    @MainActor
    func testSessionConsoleApprovingAPendingToolCallLeavesTheOutcomeVisible() throws {
        let app = launchWithSessionConsoleTranscript(state: "tool-call-pending-write")
        let approve = app.buttons["Create or modify a file"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))

        approve.click()

        XCTAssertFalse(app.buttons["Deny"].waitForExistence(timeout: 1), "the pending controls are gone once resolved")
        XCTAssertTrue(
            app.staticTexts["Write Sources/Talos/Legacy/Old.swift"].waitForExistence(timeout: 5),
            "the row itself remains, now showing its outcome"
        )
        XCTAssertTrue(app.staticTexts["Write · Allowed"].waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// Asserts AC5 for the denied outcome, and AC2/AC3/AC4 for the
    /// irreversible tier specifically: no keyboard shortcut approves it, and
    /// denying inline still leaves the outcome visible rather than an error
    /// treatment.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
    @MainActor
    func testSessionConsoleDenyingAPendingIrreversibleToolCallLeavesTheOutcomeVisible() throws {
        let app = launchWithSessionConsoleTranscript(state: "tool-call-pending-irreversible")
        let deny = app.buttons["Deny"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5))

        deny.click()

        XCTAssertFalse(app.buttons["Deny"].waitForExistence(timeout: 1), "the pending controls are gone once resolved")
        XCTAssertTrue(
            app.staticTexts["Delete Sources/Talos/Legacy/Old.swift"].waitForExistence(timeout: 5),
            "the row itself remains, now showing its outcome"
        )
        XCTAssertTrue(app.staticTexts["Irreversible · Denied"].waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
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
