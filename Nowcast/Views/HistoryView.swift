import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedReport: Report?
    @State private var reportPendingDelete: Report?

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
                        .contextMenu {
                            Button(role: .destructive) {
                                reportPendingDelete = report
                            } label: {
                                Label("Delete Brief…", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .confirmationDialog(
            "Delete this brief?",
            isPresented: Binding(
                get: { reportPendingDelete != nil },
                set: { if !$0 { reportPendingDelete = nil } }
            ),
            presenting: reportPendingDelete
        ) { report in
            Button("Delete", role: .destructive) {
                state.deleteReport(report)
                reportPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { reportPendingDelete = nil }
        } message: { report in
            Text("“\(report.displayTitle)” and its markdown file will be permanently removed. This can't be undone.")
        }
    }
}

private struct HistoryRow: View {
    let report: Report
    let isBigStory: Bool

    @ScaledMetric(relativeTo: .caption) private var glyphSize = 26.0

    private var tint: Color { TopicGlyph.tint(for: report.topic) }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            glyph
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if report.isUnread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .help("Unread")
                    }
                    if isBigStory {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                            .help(bigStoryTooltip)
                    }
                    if report.kind == .weeklyDigest {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption2)
                            .foregroundStyle(Color.purple)
                            .help("Weekly digest")
                    }
                    Text(report.displayTitle)
                        .font(.body)
                        .fontWeight(report.isUnread ? .semibold : .regular)
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
                .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let tone = report.sentiment {
                toneIndicator(tone)
            }
        }
        .padding(.vertical, 2)
    }

    private var glyph: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: glyphSize, height: glyphSize)
            .overlay(
                Image(systemName: TopicGlyph.symbol(for: report.topic))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            )
    }

    private func toneIndicator(_ tone: Double) -> some View {
        let color: Color = tone > 0.25 ? .green : (tone < -0.25 ? .red : .secondary)
        let symbol = tone > 0.25 ? "arrow.up.right"
            : (tone < -0.25 ? "arrow.down.right" : "arrow.left.and.right")
        return Image(systemName: symbol)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .help("Coverage tone: \(String(format: "%+.1f", tone))")
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
