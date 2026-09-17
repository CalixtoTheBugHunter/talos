import AppKit
import SwiftUI
import TalosOrchestration
import TalosProjectLibrary
import TalosUI

/// The Sessions surface's content: choose a sub-function, choose a project,
/// name what it should do, and start it — "selectable in the UI... starts a
/// session from a user action". The selector shows all four sub-functions,
/// with Advisor and Self-improver present-but-disabled; this view is the
/// content area's Sessions destination inside the shell.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
struct ContentView: View {
    let composer: SessionComposer?
    let composerUnavailableReason: String?
    let consoleViewModel: SessionConsoleViewModel
    let deniedActionNoticeCenter: DeniedActionNoticeCenter
    @Binding var isSessionConsolePresented: Bool

    /// Assistant and Automator are the two user-triggered sub-functions, both
    /// wired through the same ``SessionComposer``. Advisor and Self-improver
    /// enter from the scheduler, so the selector shows them disabled and
    /// selection can only land on the two that start from a user action.
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
        // Scrolls only when the form is taller than the content area — a
        // resizable window can be shorter than the fields, and content that
        // overflows scrolls rather than clipping, per the platform's own
        // layout behaviour.
        // https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#text-size
        ScrollView {
            VStack(alignment: .leading, spacing: Self.contentSpacing) {
                Text(verbatim: "Talos")
                    .font(.largeTitle)
                    .accessibilityLabel("Talos")

                SubFunctionSelector(selection: $selectedSubFunction)

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

                TextField("What should \(selectedName) do?", text: $intentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(Self.intentFieldLineRange)
                    .accessibilityLabel("\(selectedName) intent")

                HStack {
                    Button("Start \(selectedName) Session") { startSession() }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
    }

    private var canStartSession: Bool {
        composer != nil && projectRoot != nil && !intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The display name of the selected sub-function, for the field placeholder,
    /// button, and accessibility label. Advisor and Self-improver are never
    /// selectable here, but the switch stays total so the enum remains the
    /// single source of the cases.
    private var selectedName: String {
        switch selectedSubFunction {
        case .assistant: "Assistant"
        case .automator: "Automator"
        case .advisor: "Advisor"
        case .selfImprover: "Self-improver"
        }
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
    private static func refreshStatusText(_ outcome: SessionComposer.SpecDriveRefreshOutcome) -> String {
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

    /// Starts the selected sub-function through the shared composer. Automator's
    /// mutating tool calls hit the same Safeguards gate Assistant's do — the
    /// difference is the guideline loaded and the intent's sub-function, not a
    /// wider autonomy.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Automator#pipeline
    private func startSession() {
        guard let composer, let projectRoot else { return }
        errorMessage = nil
        let intentText = intentText
        let subFunction = selectedSubFunction
        // The console is presented from `sessionWillStart`, which fires only
        // after the project loads and the console has reset — so a failed start
        // reports its error here and never reopens the previous transcript.
        let present: @MainActor () -> Void = { isSessionConsolePresented = true }
        Task {
            do {
                switch subFunction {
                case .automator:
                    try await composer.startAutomatorSession(
                        projectRoot: projectRoot,
                        intentText: intentText,
                        console: consoleViewModel,
                        deniedNotices: deniedActionNoticeCenter,
                        sessionWillStart: present
                    )
                default:
                    try await composer.startAssistantSession(
                        projectRoot: projectRoot,
                        intentText: intentText,
                        console: consoleViewModel,
                        deniedNotices: deniedActionNoticeCenter,
                        sessionWillStart: present
                    )
                }
            } catch {
                errorMessage = "\(error)"
            }
        }
    }
}
