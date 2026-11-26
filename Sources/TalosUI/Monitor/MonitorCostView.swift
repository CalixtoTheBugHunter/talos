import SwiftUI
import TalosOrchestration

/// The Monitor Screen: every session the chosen project ran in the filtered
/// range — tokens, estimated cost, duration, and outcome — with the success
/// rate, Talos-added overhead, and a token chart over them. The footer states
/// "not a bill" in every state, including Empty, because the honesty the SPEC
/// requires is a property of the screen, not of one cell.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy
public struct MonitorCostView: View {
    @Bindable private var viewModel: MonitorCostViewModel
    private let projectRoot: URL?
    private let reloadToken: Int
    private let onChooseProject: () -> Void
    private let loadRecords: @Sendable (URL, DateInterval) async throws -> [StoredSessionRecord]
    @State private var selectedRow: MonitorCostRow.ID?

    /// `reloadToken` changes when a session is recorded, so the surface
    /// reloads on that event rather than on a timer.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
    public init(
        viewModel: MonitorCostViewModel,
        projectRoot: URL?,
        reloadToken: Int,
        onChooseProject: @escaping () -> Void,
        loadRecords: @escaping @Sendable (URL, DateInterval) async throws -> [StoredSessionRecord]
    ) {
        self.viewModel = viewModel
        self.projectRoot = projectRoot
        self.reloadToken = reloadToken
        self.onChooseProject = onChooseProject
        self.loadRecords = loadRecords
    }

    private struct LoadKey: Equatable {
        let projectRoot: URL?
        let filter: MonitorFilter
        let reloadToken: Int
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
            Divider()
            pricesFooter
        }
        .navigationTitle("Monitor")
        .task(id: LoadKey(projectRoot: projectRoot, filter: viewModel.filter, reloadToken: reloadToken)) {
            guard let projectRoot else {
                viewModel.showEmpty(.noProject)
                return
            }
            let loadRecords = loadRecords
            await viewModel.load(filter: viewModel.filter) { interval in
                try await loadRecords(projectRoot, interval)
            }
        }
    }

    // MARK: Filters

    /// One row when it fits, stacked when it does not — at 200% text the
    /// controls wrap rather than clip.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#text-size
    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                projectControls
                Spacer()
                pickers
            }
            VStack(alignment: .leading) {
                projectControls
                pickers
            }
        }
        .padding()
    }

    private var projectControls: some View {
        HStack {
            Text(verbatim: projectRoot.map { "Project: \($0.lastPathComponent)" } ?? "No project chosen")
            Button("Choose Project Folder…", action: onChooseProject)
                .accessibilityHint("Chooses the project the Monitor and Sessions show")
        }
    }

    /// macOS draws a Picker's title as separate text beside a popup that
    /// exposes only its value, so the popup is labeled explicitly — otherwise
    /// VoiceOver hears "All sub-functions" with no hint what it filters.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#voiceover
    @ViewBuilder
    private var pickers: some View {
        Picker("Time range", selection: $viewModel.filter.timeRange) {
            ForEach(MonitorTimeRange.allCases) { range in
                Text(verbatim: range.title).tag(range)
            }
        }
        .fixedSize()
        .accessibilityLabel("Time range")
        Picker("Sub-function", selection: $viewModel.filter.subFunction) {
            ForEach(MonitorSubFunctionFilter.allCases) { filter in
                Text(verbatim: filter.title).tag(filter)
            }
        }
        .fixedSize()
        .accessibilityLabel("Sub-function")
    }

    // MARK: States

    /// The message states fill and centre in the detail area; the Ready list
    /// fills on its own — a `List` must not be wrapped in a `maxHeight:
    /// .infinity` frame, which drives an AppKit table layout loop that hangs
    /// the window.
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case let .empty(reason):
            emptyState(reason)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            HStack {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(verbatim: "Reading this project's session records.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .ready(rows):
            readyList(rows)
        case let .failed(message):
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
                Text(verbatim: message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func emptyState(_ reason: MonitorEmptyReason) -> some View {
        switch reason {
        case .noProject:
            ContentUnavailableView {
                Label("No project chosen", systemImage: "chart.bar")
            } description: {
                Text(verbatim: Self.noProjectCopy)
            } actions: {
                Button("Choose Project Folder…", action: onChooseProject)
            }
        case .notATalosProject:
            ContentUnavailableView(
                "This folder is not a Talos project yet",
                systemImage: "chart.bar",
                description: Text(verbatim: Self.notATalosProjectCopy)
            )
        case .noSessions:
            ContentUnavailableView(
                "No sessions in this range",
                systemImage: "chart.bar",
                description: Text(verbatim: Self.noSessionsCopy)
            )
        }
    }

    private static let noProjectCopy =
        "Choose a project folder to see its sessions' tokens, estimated cost, duration, and outcome."
    private static let notATalosProjectCopy =
        "It has no .talos/ directory, so it has run no sessions. Start one from Sessions."
    private static let noSessionsCopy = "Sessions this project runs appear here with their tokens, estimated cost, "
        + "duration, and outcome. A longer time range may include more."

    /// Summary, chart, then one row per session — all in one list so the whole
    /// surface scrolls at 200% text. Rows are selectable so arrow keys move
    /// through them.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#no-mouse-only-paths
    private func readyList(_ rows: [MonitorCostRow]) -> some View {
        List(selection: $selectedRow) {
            Section {
                if let rate = viewModel.successRate {
                    successRateSummary(rate)
                }
                if let overhead = viewModel.overhead {
                    overheadHeader(overhead)
                }
            }
            if let chart = viewModel.chart {
                Section {
                    MonitorTokenChart(data: chart)
                }
            }
            Section("Sessions, oldest first") {
                ForEach(rows) { row in
                    costRow(row)
                        .tag(row.id)
                }
            }
        }
    }

    // MARK: Rows and summaries

    /// Combined into one accessibility element so VoiceOver reads the whole
    /// session — the non-visual equivalent carries the estimate label too, or
    /// it is a bill to a VoiceOver user. Nothing here is distinguished by colour.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#never-by-color-alone
    private func costRow(_ row: MonitorCostRow) -> some View {
        VStack(alignment: .leading) {
            Text(verbatim: row.title)
            Text(verbatim: row.outcomeSummary)
            Text(verbatim: row.costSummary)
            secondary(row.startedSummary)
            secondary(row.durationSummary)
            secondary(row.tokensSummary)
            secondary(row.overheadSummary)
            if let sources = row.overheadSources {
                secondary(sources)
            }
            if let flag = row.overheadFlag {
                flagLabel(flag)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: Self.rowAccessibilityLabel(row)))
    }

    private func secondary(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private static func rowAccessibilityLabel(_ row: MonitorCostRow) -> String {
        spoken([
            row.title, row.outcomeSummary, row.costSummary, row.startedSummary, row.durationSummary,
            row.tokensSummary, row.overheadSummary, row.overheadSources, row.overheadFlag
        ])
    }

    /// Each present part as its own sentence, so VoiceOver pauses between them.
    private static func spoken(_ parts: [String?]) -> String {
        parts.compactMap(\.self).map { "\($0)." }.joined(separator: " ")
    }

    /// The rate, what `Succeeded` means, and what was excluded — one
    /// accessibility element so the qualifiers are never heard apart from it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
    private func successRateSummary(_ rate: MonitorSuccessRateSummary) -> some View {
        VStack(alignment: .leading) {
            Text(verbatim: rate.headline)
            if let caveat = rate.caveat {
                secondary(caveat)
            }
            if let exclusions = rate.exclusions {
                secondary(exclusions)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: Self.spoken([rate.headline, rate.caveat, rate.exclusions])))
    }

    /// The pooled overhead, its coverage, and the flag. The flag is a symbol
    /// and words — never colour alone — and the whole header is one
    /// accessibility element so VoiceOver reads the coverage with the figure.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#never-by-color-alone
    private func overheadHeader(_ overhead: MonitorOverheadSummary) -> some View {
        VStack(alignment: .leading) {
            Text(verbatim: overhead.headline)
            secondary(overhead.coverage)
            if let flag = overhead.flag {
                flagLabel(flag)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: Self.spoken([overhead.headline, overhead.coverage, overhead.flag])))
    }

    private func flagLabel(_ flag: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            Text(verbatim: flag)
        }
        .font(.footnote.bold())
    }

    private var pricesFooter: some View {
        Text(verbatim: "Estimates only — not a bill. Prices as of \(Self.dateText(viewModel.pricesEffectiveDate)).")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding()
    }

    /// Formatted in UTC, the zone the effective date is set in, so the "as of"
    /// day reads the same everywhere rather than shifting a day by local time.
    private static func dateText(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC") ?? .current
        return date.formatted(style)
    }
}
