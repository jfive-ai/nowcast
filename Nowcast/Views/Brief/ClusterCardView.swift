import SwiftUI

/// A single story cluster rendered as a richer card: a rank badge + headline,
/// source-tinted citation host chips, the summary, and styled counterpoint /
/// not-covered callouts, with a subtle feedback control cluster and hover
/// elevation. Feedback persistence stays in `ReportView` via `onToggle`.
struct ClusterCardView: View {
    let cluster: BriefingResult.Cluster
    let rank: Int
    let feedbackKinds: Set<Feedback.Kind>
    let urlIndex: [String: PersistedItem]
    let onToggle: (Feedback.Kind) -> Void

    @State private var hovering = false

    private static let feedbackButtons: [Feedback.Kind] = [.star, .thumbsUp, .thumbsDown, .dismiss]

    var body: some View {
        Card(elevated: hovering) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                header
                if !hostChips.isEmpty {
                    FlowLayout {
                        ForEach(hostChips) { chip in
                            Chip(chip.host, systemImage: chip.symbol, tint: chip.tint)
                        }
                    }
                }
                Text(cluster.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let cp = cluster.counterpoint, !cp.isEmpty {
                    callout(color: .orange, symbol: "exclamationmark.triangle.fill", label: "Counterpoint", text: cp)
                }
                if let gap = cluster.gap, !gap.isEmpty {
                    callout(color: .blue, symbol: "questionmark.circle.fill", label: "Not covered", text: gap)
                }
            }
        }
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Text("\(rank)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 22, height: 22)

            Text(cluster.headline)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Theme.Spacing.sm)

            feedbackControls
        }
    }

    private var feedbackControls: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Self.feedbackButtons, id: \.self) { kind in
                let active = feedbackKinds.contains(kind)
                Button {
                    onToggle(kind)
                } label: {
                    Image(systemName: kind.symbol)
                        .symbolVariant(active ? .fill : .none)
                        .font(.caption)
                        .foregroundStyle(active ? kind.tint : .secondary)
                }
                .buttonStyle(.plain)
                .help(kind.displayName)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.Colors.cardFillElevated))
    }

    private func callout(color: Color, symbol: String, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2.bold())
                    .foregroundStyle(color)
                    .textCase(.uppercase)
                Text(text)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(color.opacity(0.08))
        )
    }

    // MARK: - Citation host chips

    private struct HostChip: Identifiable {
        let host: String
        let kind: SourceKind?
        var id: String { host }
        var symbol: String { kind.map(SourcePalette.symbol(for:)) ?? SourcePalette.unknownSymbol }
        var tint: Color { kind.map(SourcePalette.color(for:)) ?? SourcePalette.unknownColor }
    }

    /// Hosts from the cluster's citations, deduped and source-tinted, capped so
    /// a citation-heavy cluster doesn't overflow the card.
    private var hostChips: [HostChip] {
        var seen = Set<String>()
        var out: [HostChip] = []
        for citation in cluster.citations {
            let host = URL(string: citation)?.host?.replacingOccurrences(of: "www.", with: "") ?? citation
            guard !host.isEmpty, !seen.contains(host) else { continue }
            seen.insert(host)
            let kind = urlIndex[MarkdownLinkText.normalize(citation)]?.sourceKind
            out.append(HostChip(host: host, kind: kind))
            if out.count >= 6 { break }
        }
        return out
    }
}
