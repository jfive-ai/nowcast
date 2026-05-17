import SwiftUI

/// Right-hand "show your work" drawer (P6-2). For each cluster of the
/// current report, lists every claim with the source items that supported
/// it. Mirrors the chat drawer pattern but is read-only.
struct ProvenanceView: View {
    let rows: [ProvenanceBuilder.ClusterRows]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(rows) { group in
                            cluster(group)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var header: some View {
        HStack {
            Label("Provenance", systemImage: "checkmark.seal")
                .font(.headline)
            Spacer()
            Text("\(claimCount) claims · \(itemCount) items")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 32)).foregroundStyle(.secondary)
            Text("No structured claims to show").font(.headline)
            Text("This report doesn't carry the per-claim citation block — usually only briefs generated before P4-2.")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cluster(_ group: ProvenanceBuilder.ClusterRows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.headline).font(.subheadline).bold()
            ForEach(group.rows) { row in
                claimRow(row)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }

    @ViewBuilder
    private func claimRow(_ row: ProvenanceBuilder.ClaimRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "quote.bubble")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(row.claim.text)
                    .font(.caption)
            }
            if row.supportingItems.isEmpty {
                Label("No matched items in source set", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
            } else {
                ForEach(row.supportingItems) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.caption2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Link(destination: item.canonicalURL) {
                                Text(item.title)
                                    .font(.caption).bold()
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            HStack(spacing: 4) {
                                Text(item.sourceKind.displayName)
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text("·").font(.caption2).foregroundStyle(.secondary)
                                Text(item.canonicalURL.host?.replacingOccurrences(of: "www.", with: "") ?? "")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.05)))
                }
            }
            if !row.unmatchedCitations.isEmpty {
                Text("Other cites: \(row.unmatchedCitations.prefix(3).joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var claimCount: Int { rows.reduce(0) { $0 + $1.rows.count } }
    private var itemCount: Int {
        rows.flatMap { $0.rows.flatMap(\.supportingItems) }
            .reduce(into: Set<UUID>()) { $0.insert($1.id) }
            .count
    }
}
