import SwiftUI
import Charts

/// Per-source success / freshness / latency over the last 30 days. Settings →
/// "Source health" tab. Populated as the pipeline runs against each adapter.
struct SourceHealthView: View {
    @EnvironmentObject private var state: AppState
    @State private var rows: [SourceHealth] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Source health")
                    .font(.title2).bold()
                Spacer()
                Text("Last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }

            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No source runs yet")
                        .font(.headline)
                    Text("Generate a report to start populating per-source stats.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                successRateChart
                freshnessChart
                latencyTable
            }
        }
        .padding()
        .onAppear { refresh() }
    }

    private var successRateChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Success rate")
                .font(.headline)
            Chart(rows) { row in
                BarMark(
                    x: .value("Source", row.sourceKind.displayName),
                    y: .value("Success rate", row.successRate * 100)
                )
                .foregroundStyle(barColor(row.successRate))
                .annotation(position: .top) {
                    Text(String(format: "%.0f%%", row.successRate * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: 0...110)
            .frame(height: 140)
        }
    }

    private var freshnessChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Items: returned vs fresh")
                .font(.headline)
            Chart(rows) { row in
                BarMark(
                    x: .value("Source", row.sourceKind.displayName),
                    y: .value("Total", row.totalReturned)
                )
                .foregroundStyle(.gray.opacity(0.35))
                BarMark(
                    x: .value("Source", row.sourceKind.displayName),
                    y: .value("Fresh", row.totalFresh)
                )
                .foregroundStyle(Color.accentColor)
            }
            .frame(height: 140)
        }
    }

    private var latencyTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Runs · latency · last error")
                .font(.headline)
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.sourceKind.displayName)
                        .frame(width: 140, alignment: .leading)
                        .bold()
                    Text("\(row.runs) runs")
                        .frame(width: 80, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(row.avgLatencySeconds.map { String(format: "%.2fs", $0) } ?? "—")
                        .frame(width: 80, alignment: .leading)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let err = row.lastError, !err.isEmpty {
                        Text(err)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("OK")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func barColor(_ rate: Double) -> Color {
        if rate >= 0.9 { return .green }
        if rate >= 0.5 { return .yellow }
        return .red
    }

    private func refresh() {
        rows = (try? state.sourceHealthRows()) ?? []
    }
}
