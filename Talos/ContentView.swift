import AppKit
import SwiftUI
import TalosOrchestration
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
    @State private var refreshStatus: String?
    @State private var isRefreshingSpecDrive = false

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

            HStack {
                Button("Start Assistant Session") { startSession() }
                    .disabled(!canStartSession)

                Button("Refresh Spec Drive") { refreshSpecDrive() }
                    .disabled(!canRefreshSpecDrive)
            }

            if let refreshStatus {
                Text(refreshStatus).foregroundStyle(.secondary)
            }

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

    /// No intent text — Talos authors that — so it needs only a project, and
    /// stays disabled while a refresh is running.
    private var canRefreshSpecDrive: Bool {
        composer != nil && projectRoot != nil && !isRefreshingSpecDrive
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

    /// Runs the refresh in the session console like any other agent session —
    /// the user watches its output and approves its writes there. The console
    /// opens only once a run starts, so a no-Spec-Drive project gets the answer
    /// rather than a console that never fills.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
    private func refreshSpecDrive() {
        guard let composer, let projectRoot else { return }
        errorMessage = nil
        refreshStatus = nil
        isRefreshingSpecDrive = true
        Task {
            do {
                let outcome = try await composer.refreshSpecDriveIndex(
                    projectRoot: projectRoot,
                    console: consoleViewModel,
                    deniedNotices: deniedActionNoticeCenter,
                    sessionWillStart: { isSessionConsolePresented = true }
                )
                refreshStatus = Self.refreshStatusText(outcome)
            } catch {
                errorMessage = "\(error)"
            }
            isRefreshingSpecDrive = false
        }
    }

    /// Names how the run ended before the counts: a failed, denied, or stopped
    /// run leaves the index holding whatever was already fetched, which a plain
    /// count would read as a refresh that found nothing.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    private static func refreshStatusText(_ outcome: AssistantSessionComposer.SpecDriveRefreshOutcome) -> String {
        switch outcome {
        case .noSpecDrive:
            "This project declares no Spec Drive. Add one in .talos/spec.yaml, then refresh."
        case let .refreshed(pageCount, sectionCount, session):
            switch session {
            case .succeeded:
                "Indexed \(count(sectionCount, of: "section")) from \(count(pageCount, of: "Spec Drive page"))."
            case .failed, .denied, .stopped:
                """
                The fetch run \(sessionEnding(session)), so the index still holds only what was already \
                fetched: \(count(sectionCount, of: "section")) from \
                \(count(pageCount, of: "Spec Drive page")). The console above says what happened.
                """
            }
        }
    }

    private static func sessionEnding(_ session: SessionOutcomeClassification) -> String {
        switch session {
        case .succeeded: "finished"
        case .failed: "failed"
        case .denied: "was denied"
        case .stopped: "was stopped"
        }
    }

    private static func count(_ number: Int, of noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
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
