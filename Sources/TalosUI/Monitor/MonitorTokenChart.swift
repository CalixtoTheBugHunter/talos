import Charts
import SwiftUI
import TalosAdapters
import TalosOrchestration

/// One bar: a session the agent reported tokens for, and the total it reported.
public struct MonitorTokenChartPoint: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The bar's category — the session's position in the list, oldest first,
    /// so each bar names the row it plots.
    public let label: String
    public let totalTokens: Int
}

/// What the chart plots. A session with no token count gets no bar and is
/// counted instead — a zero bar would read as a cheap session.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
public struct MonitorTokenChartData: Equatable, Sendable {
    public let points: [MonitorTokenChartPoint]
    public let notPlottedCount: Int

    public init(records: [StoredSessionRecord]) {
        var points: [MonitorTokenChartPoint] = []
        var notPlotted = 0
        for (index, record) in records.enumerated() {
            guard case let .measured(counts, _) = record.tokenReport else {
                notPlotted += 1
                continue
            }
            let total = counts.input + counts.output + (counts.cacheCreation ?? 0) + (counts.cacheRead ?? 0)
            points.append(MonitorTokenChartPoint(id: record.id, label: "Session \(index + 1)", totalTokens: total))
        }
        self.points = points
        notPlottedCount = notPlotted
    }

    /// The chart's whole reading in words, so it is not only a picture.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Tone#structure-over-prose
    public var summary: String {
        let plotted = "\(points.count) \(points.count == 1 ? "session" : "sessions") plotted"
        let missing = notPlottedCount > 0 ? "; \(notPlottedCount) not plotted (no token count)" : ""
        return "Tokens per session: \(plotted)\(missing). Each value is listed below."
    }
}

/// Tokens the agent reported, one bar per session. One series in the system's
/// default style, no tooltip, and every value in the accessibility chart
/// descriptor and in the rows below.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#voiceover
struct MonitorTokenChart: View {
    let data: MonitorTokenChartData

    var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: data.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            if !data.points.isEmpty {
                Chart(data.points) { point in
                    BarMark(
                        x: .value("Session", point.label),
                        y: .value("Tokens", point.totalTokens)
                    )
                }
                .chartXAxisLabel("Session, oldest first")
                .chartYAxisLabel("Tokens reported by the agent")
                .frame(minHeight: Self.minimumHeight)
                .accessibilityChartDescriptor(MonitorTokenChartDescriptor(data: data))
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: data.summary))
    }

    private static let minimumHeight: CGFloat = 140
}

/// The chart as VoiceOver's data table and audio graph.
private struct MonitorTokenChartDescriptor: AXChartDescriptorRepresentable {
    let data: MonitorTokenChartData

    func makeChartDescriptor() -> AXChartDescriptor {
        let maximum = Double(data.points.map(\.totalTokens).max() ?? 0)
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Session",
            categoryOrder: data.points.map(\.label)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Tokens reported by the agent",
            range: 0 ... max(maximum, 1),
            gridlinePositions: []
        ) { "\(Int($0)) tokens" }
        let series = AXDataSeriesDescriptor(
            name: "Tokens per session",
            isContinuous: false,
            dataPoints: data.points.map { AXDataPoint(x: $0.label, y: Double($0.totalTokens)) }
        )
        return AXChartDescriptor(
            title: "Tokens per session",
            summary: data.summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
