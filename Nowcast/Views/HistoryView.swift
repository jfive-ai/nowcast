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
                    HistoryRow(report: report)
                        .tag(Optional(report))
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct HistoryRow: View {
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(report.topic)
                .font(.body)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(report.generatedAt, style: .date)
                Text("·")
                Text(report.window.displayName)
                Text("·")
                Text(ByteCountFormatter.string(fromByteCount: report.byteSize, countStyle: .file))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
