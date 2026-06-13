import SwiftUI

/// Side-by-side comparison of two reports on the same topic / preset (P6-3).
/// Each column renders its brief through the same sectionized layout as the
/// main report view (V3), so equivalent sections look identical and are easy to
/// compare; the cluster-level delta (added / continuing / dropped) is shown as
/// color-coded chips at the top.
struct CompareReportsView: View {
    @EnvironmentObject private var state: AppState
    let left: Report
    let right: Report

    @State private var leftMarkdown: String = ""
    @State private var rightMarkdown: String = ""
    @State private var leftIndex: [String: PersistedItem] = [:]
    @State private var rightIndex: [String: PersistedItem] = [:]
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader("Compare", systemImage: "rectangle.split.2x1",
                              accent: .accentColor)
                Text("\(left.generatedAt.formatted(date: .abbreviated, time: .omitted))  ↔  \(right.generatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            FlowLayout {
                Chip("\(left.sourceCount) → \(right.sourceCount) items", systemImage: "tray.full")
                if let lc = left.usdCost, let rc = right.usdCost {
                    Chip(String(format: "$%.4f → $%.4f", lc, rc), systemImage: "dollarsign.circle")
                }
            }
            .frame(maxWidth: 280)
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Delta strip

    private var deltaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(delta.newClusters, id: \.id) { c in
                    deltaChip("New", systemImage: "plus.circle.fill", color: .green, label: c.headline)
                }
                ForEach(0..<delta.continuingClusters.count, id: \.self) { idx in
                    deltaChip("Continuing", systemImage: "arrow.right.circle.fill", color: .blue,
                              label: delta.continuingClusters[idx].current.headline)
                }
                ForEach(delta.droppedClusters, id: \.id) { c in
                    deltaChip("Dropped", systemImage: "minus.circle.fill", color: .gray, label: c.headline)
                }
                if delta.isEmpty {
                    Text("No structured-cluster differences detected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Colors.cardFill)
    }

    private func deltaChip(_ kind: String, systemImage: String, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.caption2)
                .accessibilityHidden(true)
            Text(kind).font(.caption2.bold())
            Text(label).font(.caption).foregroundStyle(.primary).lineLimit(1)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - Split panes

    private var split: some View {
        HSplitView {
            pane(report: left, markdown: leftMarkdown, urlIndex: leftIndex)
            pane(report: right, markdown: rightMarkdown, urlIndex: rightIndex)
        }
    }

    private func pane(report: Report, markdown: String, urlIndex: [String: PersistedItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.md, pinnedViews: [.sectionHeaders]) {
                Section {
                    BriefBodyView(markdown: markdown, urlIndex: urlIndex)
                        .textSelection(.enabled)
                        .padding(.top, Theme.Spacing.sm)
                } header: {
                    paneHeader(report: report)
                }
            }
            .padding(14)
        }
    }

    private func paneHeader(report: Report) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(TopicGlyph.tint(for: report.topic).opacity(0.16))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: TopicGlyph.symbol(for: report.topic))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TopicGlyph.tint(for: report.topic))
                        .accessibilityHidden(true)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(report.displayTitle).font(.subheadline.bold()).lineLimit(1)
                Text(report.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(.regularMaterial)
    }

    private var pairKey: String { "\(left.id.uuidString)-\(right.id.uuidString)" }

    private func reload() {
        leftMarkdown = state.loadMarkdown(for: left)
        rightMarkdown = state.loadMarkdown(for: right)
        leftIndex = MarkdownLinkText.buildIndex(items: state.itemsForReport(left.id))
        rightIndex = MarkdownLinkText.buildIndex(items: state.itemsForReport(right.id))
        let leftClusters = state.clusters(forReport: left.id)
        let rightClusters = state.clusters(forReport: right.id)
        delta = BriefDiff.diff(current: rightClusters, prior: leftClusters)
    }
}
