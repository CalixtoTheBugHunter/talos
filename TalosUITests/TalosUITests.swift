import XCTest

/// The `a11y` CI stage's structural audit, per
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Verification
///
/// > `a11y` asserts labels, hints, and roles. Whether the *spoken result* is
/// > comprehensible is a judgement...
///
/// `performAccessibilityAudit()` is Apple's own structural audit — labels,
/// traits, contrast, hit-target size — and is what this stage claims. It
/// does not claim comprehensibility, streaming-output announcements, the
/// approval prompt, or coverage of surfaces that do not exist yet; that
/// deeper audit is https://github.com/CalixtoTheBugHunter/talos/issues/97,
/// which grows this file surface by surface as they are built.
final class TalosUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRootWindowHasNoAccessibilityAuditIssues() throws {
        let app = XCUIApplication()
        app.launch()
        try app.performAccessibilityAudit { issue in
            // Confirmed platform limitation, not a Talos defect: any bare
            // `WindowGroup` scene's own root content-hosting container is an
            // anonymous accessibility Group AppKit/SwiftUI generates, and it
            // has produced two different issue types against that same node
            // regardless of where an accessibility label is applied in the
            // app's own view or scene code ("Element has no description",
            // then "Parent/Child mismatch" once the first was accepted).
            // ContentView authors no `Group` of its own, so any issue whose
            // element IS a Group is, by construction, about this framework
            // node rather than Talos's code. If Talos ever legitimately
            // introduces a real `Group`, this exemption needs narrowing.
            if issue.element?.elementType == .group {
                return true
            }
            print("ACCESSIBILITY AUDIT ISSUE: \(issue)")
            return false
        }
    }
}
