import SwiftUI

/// Side-by-side comparison of two reports on the same topic / preset
/// (P6-3). Renders both bodies in parallel scroll columns and prints the
/// cluster-level delta (added / continuing / dropped) at the top.
struct CompareReportsView: View {
    @EnvironmentObject private var state: AppState
    let left: Report
    let right: Report

    @State private var leftMarkdown: String = ""
    @State private var rightMarkdown: String = ""
    @State private var delta: BriefDiff.BriefDelta = .init()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            deltaStrip
            Divider()
            split
        }
        .task(id: pairKey) { reload() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Compare").font(.headline)
                Text("\(left.topic) · \(left.generatedAt.formatted(date: .abbreviated, time: .omitted))  ↔  \(right.topic) · \(right.generatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                metric("Items", "\(left.sourceCount) → \(right.sourceCount)")
                if let lc = left.usdCost, let rc = right.usdCost {
                    metric("Cost", String(format: "$%.4f → $%.4f", lc, rc))
                }
            }
        }
        .padding(12)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private var deltaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(delta.newClusters, id: \.id) { c in
                    deltaChip("New", color: .green, label: c.headline)
                }
                ForEach(0..<delta.continuingClusters.count, id: \.self) { idx in
                    deltaChip("Continuing", color: .blue, label: delta.continuingClusters[idx].current.headline)
                }
                ForEach(delta.droppedClusters, id: \.id) { c in
                    deltaChip("Dropped", color: .gray, label: c.headline)
                }
                if delta.isEmpty {
                    Text("No structured-cluster differences detected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(Color.secondary.opacity(0.05))
    }

    private func deltaChip(_ kind: String, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Text(kind).font(.caption2.bold())
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(color.opacity(0.20))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(label).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.08)))
    }

    private var split: some View {
        HSplitView {
            pane(title: leftTitle, markdown: leftMarkdown)
            pane(title: rightTitle, markdown: rightMarkdown)
        }
    }

    private func pane(title: String, markdown: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold()).padding(.bottom, 2)
                Text(markdown)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
    }

    private var leftTitle: String { "\(left.generatedAt.formatted(date: .abbreviated, time: .shortened))" }
    private var rightTitle: String { "\(right.generatedAt.formatted(date: .abbreviated, time: .shortened))" }

    private var pairKey: String { "\(left.id.uuidString)-\(right.id.uuidString)" }

    private func reload() {
        leftMarkdown = state.loadMarkdown(for: left)
        rightMarkdown = state.loadMarkdown(for: right)
        let leftClusters = state.clusters(forReport: left.id)
        let rightClusters = state.clusters(forReport: right.id)
        delta = BriefDiff.diff(current: rightClusters, prior: leftClusters)
    }
}
