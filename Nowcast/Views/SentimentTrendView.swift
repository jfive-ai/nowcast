import SwiftUI
import Charts

/// Per-preset sentiment trend over time. Plots the LLM-reported
/// coverage sentiment of each brief on a [-1, +1] axis with a neutral=0
/// baseline. Green above 0 = bullish/optimistic coverage; red below = bearish.
///
/// Hides itself behind an empty state when fewer than three briefs carry a
/// sentiment value — a two-point line tells the user nothing useful.
struct SentimentTrendView: View {
    let presetName: String
    let reports: [Report]

    private var scored: [Report] {
        reports
            .filter { $0.sentiment != nil && $0.kind == .daily }
            .sorted { $0.generatedAt < $1.generatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if scored.count < 3 {
                emptyState
            } else {
                chart
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 320)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sentiment trend").font(.headline)
                Text(presetName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(color: .green, label: "Bullish")
            legendDot(color: .secondary, label: "Neutral")
            legendDot(color: .red, label: "Bearish")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Not enough data yet")
                .font(.headline)
            Text("Generate at least three briefs for this preset to see a trend.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chart: some View {
        Chart {
            ForEach(scored, id: \.id) { report in
                LineMark(
                    x: .value("Date", report.generatedAt),
                    y: .value("Sentiment", report.sentiment ?? 0)
                )
                .foregroundStyle(Color.accentColor)

                AreaMark(
                    x: .value("Date", report.generatedAt),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Sentiment", report.sentiment ?? 0)
                )
                .foregroundStyle(
                    (report.sentiment ?? 0) >= 0
                        ? Color.green.opacity(0.18)
                        : Color.red.opacity(0.18)
                )

                PointMark(
                    x: .value("Date", report.generatedAt),
                    y: .value("Sentiment", report.sentiment ?? 0)
                )
                .symbolSize(40)
                .foregroundStyle(
                    (report.sentiment ?? 0) >= 0 ? Color.green : Color.red
                )
                .annotation(position: .top, alignment: .center) {
                    if let r = report.sentimentRationale, !r.isEmpty {
                        Text(r)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                }
            }
            RuleMark(y: .value("Neutral", 0))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
        }
        .chartYScale(domain: -1...1)
        .chartYAxis {
            AxisMarks(values: [-1, -0.5, 0, 0.5, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(String(format: "%+.1f", d)).font(.caption2)
                    }
                }
            }
        }
    }
}
