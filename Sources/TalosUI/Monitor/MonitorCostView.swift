import SwiftUI

/// The Monitor's cost surface: per-session estimated cost, and the date the
/// shipped prices were set so the user knows how current the basis is. The
/// footer states "not a bill" in every state, including Empty, because the
/// honesty the SPEC requires is a property of the screen, not of one cell.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy
public struct MonitorCostView: View {
    private let viewModel: MonitorCostViewModel

    public init(viewModel: MonitorCostViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            pricesFooter
        }
        .navigationTitle("Monitor")
    }

    /// The message states fill and centre in the detail area; the Ready list
    /// fills on its own — a `List` must not be wrapped in a `maxHeight:
    /// .infinity` frame, which drives an AppKit table layout loop that hangs
    /// the window.
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            ContentUnavailableView(
                "No estimated costs yet",
                systemImage: "chart.bar",
                description: Text(verbatim: "Estimated costs appear here once this project has run a session.")
            )
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
            List(rows) { row in
                costRow(row)
            }
        case let .failed(message):
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
                Text(verbatim: message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Cost first, then the counts it is mapped from. Combined into one
    /// accessibility element so VoiceOver reads the whole line — the non-visual
    /// equivalent carries the estimate label too, or it is a bill to a
    /// VoiceOver user. Nothing here is distinguished by colour.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#never-by-color-alone
    private func costRow(_ row: MonitorCostRow) -> some View {
        VStack(alignment: .leading) {
            Text(verbatim: row.title)
            Text(verbatim: row.costSummary)
            Text(verbatim: row.tokensSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(row.title). \(row.costSummary). \(row.tokensSummary)."))
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
