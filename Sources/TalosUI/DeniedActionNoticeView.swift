import SwiftUI

/// The notice itself — a name and target, and the word "Denied", never an
/// error color or an error icon. See § Denial is not failure.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
struct DeniedActionNoticeView: View {
    let notice: DeniedActionNotice

    var body: some View {
        Label(sentence, systemImage: "hand.raised")
            .foregroundStyle(.secondary)
            .padding()
            .accessibilityElement(children: .combine)
    }

    private var sentence: String {
        let target = notice.requestPrompt.isEmpty
            ? SafeguardsApprovalCopy.operationLabel(for: notice.action)
            : notice.requestPrompt
        return "Denied: \(target)"
    }
}
