import SwiftUI
import TalosProjectLibrary

/// The in-session choice of sub-function. All four are present; the two that
/// activate today are selectable and the two that do not are "disabled and
/// marked 'Coming soon'", because DoD item 6 requires Advisor and Self-improver
/// "visible and marked 'Coming soon'".
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#every-surface-placed
///
/// Selection is carried by the radio symbol's shape, and the coming-soon state
/// by a text label as well as the disabled control — never by color alone.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#never-by-color-alone
struct SubFunctionSelector: View {
    @Binding var selection: SubFunction

    var body: some View {
        VStack(alignment: .leading) {
            Text("Sub-function")
                .font(.headline)
            ForEach(SubFunction.allCases, id: \.self) { subFunction in
                row(for: subFunction)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sub-function")
    }

    private func row(for subFunction: SubFunction) -> some View {
        let comingSoon = Self.isComingSoon(subFunction)
        let isSelected = subFunction == selection
        return Button {
            selection = subFunction
        } label: {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                Text(Self.displayName(subFunction))
                if comingSoon {
                    Text("Coming soon")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(comingSoon)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(
            comingSoon
                ? "\(Self.displayName(subFunction)), Coming soon"
                : Self.displayName(subFunction)
        )
    }

    /// Advisor and Self-improver activate from the scheduler, not a user
    /// starting a session, so they are present-but-disabled in the MVP shell.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Home#how-talos-works
    static func isComingSoon(_ subFunction: SubFunction) -> Bool {
        switch subFunction {
        case .assistant, .automator: false
        case .advisor, .selfImprover: true
        }
    }

    static func displayName(_ subFunction: SubFunction) -> String {
        switch subFunction {
        case .assistant: "Assistant"
        case .automator: "Automator"
        case .advisor: "Advisor"
        case .selfImprover: "Self-improver"
        }
    }
}
