import XCTest

/// The shell and navigation surface of
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation —
/// every top-level surface reachable, the sub-function selector's coming-soon
/// entries, surface cycling, and the auxiliary Starting Guide window, each
/// driven keyboard- or menu-first so there is no mouse-only path.
final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Every top-level surface is reachable from the View menu, and the two
    /// cycle commands carry `⌘⌥→` / `⌘⌥←` beside them — "a keystroke with no
    /// menu entry is one the accessibility gate cannot see".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#menus-carry-the-shortcuts
    @MainActor
    func testEverySurfaceIsReachableFromTheViewMenu() {
        let app = XCUIApplication()
        app.launch()

        app.menuBarItems["View"].click()

        for title in ["Sessions", "Monitor", "Chat History", "Local Memories", "Project Library"] {
            XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 5), "\(title) is in the View menu")
        }
        XCTAssertTrue(app.menuItems["Next Surface"].exists)
        XCTAssertTrue(app.menuItems["Previous Surface"].exists)
    }

    /// Selecting a surface shows its content in the content area; a placeholder
    /// surface's Empty state is proof the navigation switched.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#every-surface-placed
    @MainActor
    func testViewMenuNavigatesToASurface() throws {
        let app = XCUIApplication()
        app.launch()

        app.menuBarItems["View"].click()
        app.menuItems["Monitor"].click()

        XCTAssertTrue(
            app.staticTexts["This surface is not available yet."].waitForExistence(timeout: 5),
            "selecting Monitor shows the Monitor surface"
        )
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// `⌘⌥→` moves to the next surface in sidebar order, driven by keyboard
    /// alone with no pointer path.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#moving-between-surfaces
    @MainActor
    func testNextSurfaceShortcutCyclesToTheNextSurface() {
        let app = XCUIApplication()
        app.launch()

        app.typeKey(.rightArrow, modifierFlags: [.command, .option])

        XCTAssertTrue(
            app.staticTexts["This surface is not available yet."].waitForExistence(timeout: 5),
            "⌘⌥→ from Sessions moves to the next surface"
        )
    }

    /// DoD item 6: Advisor and Self-improver are present in the sub-function
    /// selector, disabled, and marked "Coming soon" — never by color alone, so
    /// the label carries it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#every-surface-placed
    @MainActor
    func testAdvisorAndSelfImproverArePresentButDisabled() {
        let app = XCUIApplication()
        app.launch()

        let advisor = app.buttons["Advisor, Coming soon"]
        let selfImprover = app.buttons["Self-improver, Coming soon"]
        XCTAssertTrue(advisor.waitForExistence(timeout: 5))
        XCTAssertTrue(selfImprover.exists)
        XCTAssertFalse(advisor.isEnabled, "Advisor is present but disabled")
        XCTAssertFalse(selfImprover.isEnabled, "Self-improver is present but disabled")
        XCTAssertTrue(app.buttons["Assistant"].isEnabled, "Assistant is enabled")
        XCTAssertTrue(app.buttons["Automator"].isEnabled, "Automator is enabled")
    }

    /// The Sessions surface — the shell's one hand-built layout, the
    /// sub-function selector — passes Apple's structural accessibility audit,
    /// not only the inherited placeholder surfaces. Selected explicitly from the
    /// View menu rather than assumed on screen: the sidebar selection persists
    /// across launches, so a prior test that cycled away from Sessions would
    /// otherwise leave the selector off screen.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#how-the-gate-is-checked
    @MainActor
    func testSessionsSurfacePassesTheAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()

        app.menuBarItems["View"].click()
        app.menuItems["Sessions"].click()

        XCTAssertTrue(app.buttons["Assistant"].waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    /// The auxiliary window — the Starting Guide — is re-openable from the Help
    /// menu, "its own window, not a sidebar surface".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#every-surface-placed
    @MainActor
    func testStartingGuideOpensFromTheHelpMenu() {
        let app = XCUIApplication()
        app.launch()

        app.menuBarItems["Help"].click()
        // The Help menu's search field also indexes the command, so the title
        // matches more than once; the first match is the menu item itself. Wait
        // for it to exist — the menu has finished opening — before clicking, or
        // a not-yet-laid-out item is clicked at an invalid point.
        let startingGuide = app.menuItems["Starting Guide"].firstMatch
        XCTAssertTrue(startingGuide.waitForExistence(timeout: 5))
        startingGuide.click()

        XCTAssertTrue(
            app.staticTexts["The Starting Guide is not available yet."].waitForExistence(timeout: 5),
            "the Starting Guide opens in its own window"
        )
    }

    /// The shell's own elements pass Apple's structural accessibility audit,
    /// filtered to Talos-authored element types the way the main suite does.
    @MainActor
    private func assertNoTalosOwnAccessibilityIssues(on app: XCUIApplication) throws {
        var talosOwnIssues: [XCUIAccessibilityAuditIssue] = []
        // `.contrast` is dropped for the same reason as the main suite: the
        // gate verifies contrast by inheritance and `lint`, not this audit.
        try app.performAccessibilityAudit(for: .all.subtracting(.contrast)) { issue in
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
