import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedReport: Report?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Text("\(state.reports.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List(selection: $selectedReport) {
                ForEach(state.reports, id: \.self) { report in
                    HistoryRow(report: report, isBigStory: state.isBigStory(report))
                        .tag(Optional(report))
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct HistoryRow: View {
    let report: Report
    let isBigStory: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if isBigStory {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                        .help(bigStoryTooltip)
                }
                if report.kind == .weeklyDigest {
                    Label("Weekly", systemImage: "calendar.badge.clock")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.18))
                        .foregroundStyle(Color.purple)
                        .clipShape(Capsule())
                }
                Text(report.displayTitle)
                    .font(.body)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(report.generatedAt, style: .date)
                Text("·")
                Text(report.window.displayName)
                Text("·")
                Text(ByteCountFormatter.string(fromByteCount: report.byteSize, countStyle: .file))
                if let cost = report.usdCost, cost > 0 {
                    Text("·")
                    Text(Self.formatCost(cost))
                } else if let total = report.totalTokens, total > 0 {
                    Text("·")
                    Text("\(total) tok")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private static func formatCost(_ usd: Double) -> String {
        if usd < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", usd)
    }

    private var bigStoryTooltip: String {
        if let headline = report.bigStoryHeadline, !headline.isEmpty {
            return "Big story — sources converge on: \(headline)"
        }
        return "Big story — unusually high cross-source agreement"
    }
}
