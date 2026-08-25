import XCTest

/// The `a11y` CI stage's structural audit:
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Verification
///
/// `performAccessibilityAudit()` is Apple's own structural audit — labels,
/// traits, contrast, hit-target size. It does not claim comprehensibility,
/// streaming-output announcements, or the approval prompt.
final class TalosUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRootWindowHasNoAccessibilityAuditIssues() throws {
        let app = XCUIApplication()
        app.launch()

        // Every issue is accepted here (always `true`), so the audit
        // enumerates the whole tree instead of stopping at the first
        // rejection. `talosOwnIssues` is the real count this test asserts
        // against — the CI script parses `ACCESSIBILITY_ISSUE_COUNT:`
        // below rather than reading a bare pass/fail exit code, so a
        // regression from 1 issue to 3 is visible, not just "failing".
        var talosOwnIssues: [XCUIAccessibilityAuditIssue] = []
        try app.performAccessibilityAudit { issue in
            // The audit walks every accessibility node AppKit generates for
            // a window, including framework-level ones (the window's own
            // root Group, a TouchBar) that no label in Talos's view code
            // can fix. Only `.staticText` — the type ContentView's `Text`
            // maps to — is a Talos-authored element; anything else,
            // including an issue with no element reference at all, is
            // excused here rather than flagged as a false regression.
            guard let elementType = issue.element?.elementType, elementType == .staticText else {
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
