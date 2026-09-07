import AppKit
import SwiftUI
import TalosProjectLibrary
import TalosUI

/// Assistant's entry point: choose a project, name what it should do, and
/// start it — "selectable in the UI... starts a session from a user action".
/// No sidebar, project list, or session history exists yet (tracked
/// separately); this is the one control that exists today.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Assistant#pipeline
struct ContentView: View {
    let composer: AssistantSessionComposer?
    let composerUnavailableReason: String?
    let consoleViewModel: SessionConsoleViewModel
    let deniedActionNoticeCenter: DeniedActionNoticeCenter
    @Binding var isSessionConsolePresented: Bool

    /// Only ``SubFunction/assistant`` exists as a real, wired option today —
    /// Automator's own composition root is separate, not-yet-built work. A
    /// `Picker` with one enabled option is still a selection control, so
    /// "Assistant is selectable" holds without inventing Automator's
    /// presence ahead of it.
    @State private var selectedSubFunction: SubFunction = .assistant
    @State private var projectRoot: URL?
    @State private var intentText = ""
    @State private var errorMessage: String?

    private static let contentSpacing: CGFloat = 16
    private static let intentFieldLineRange = 3 ... 6
    private static let minimumWidth: CGFloat = 420
    private static let minimumHeight: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: Self.contentSpacing) {
            Text(verbatim: "Talos")
                .font(.largeTitle)
                .accessibilityLabel("Talos")

            Picker("Sub-function", selection: $selectedSubFunction) {
                Text("Assistant").tag(SubFunction.assistant)
            }
            .pickerStyle(.menu)
            .fixedSize()

            HStack {
                Button("Choose Project Folder…") { chooseProjectFolder() }
                if let projectRoot {
                    Text(projectRoot.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text("No project selected")
                        .foregroundStyle(.secondary)
                }
            }

            TextField("What should Assistant do?", text: $intentText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(Self.intentFieldLineRange)
                .accessibilityLabel("Assistant intent")

            Button("Start Assistant Session") { startSession() }
                .disabled(!canStartSession)

            if let reason = composerUnavailableReason {
                Text(reason).foregroundStyle(.red)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
    }

    private var canStartSession: Bool {
        composer != nil && projectRoot != nil && !intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectRoot = url
    }

    private func startSession() {
        guard let composer, let projectRoot else { return }
        errorMessage = nil
        isSessionConsolePresented = true
        let intentText = intentText
        Task {
            do {
                try await composer.startAssistantSession(
                    projectRoot: projectRoot,
                    intentText: intentText,
                    console: consoleViewModel,
                    deniedNotices: deniedActionNoticeCenter
                )
            } catch {
                errorMessage = "\(error)"
            }
        }
    }
}
