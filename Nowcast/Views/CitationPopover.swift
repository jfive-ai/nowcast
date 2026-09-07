import SwiftUI

/// Popover body shown when the user hovers a citation chip in
/// `MarkdownLinkText`. Surfaces the matched `PersistedItem` if one
/// exists in the brief's source set; otherwise a minimal preview of just
/// the URL host.
struct CitationPopover: View {
    @EnvironmentObject private var state: AppState
    let label: String
    let urlString: String
    let item: PersistedItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    if let symbol = sourceSymbol {
                        Image(systemName: symbol).font(.caption2)
                            .accessibilityHidden(true)
                    }
                    Text(host).font(.caption2.bold())
                }
                .foregroundStyle(sourceTint)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(sourceTint.opacity(0.14), in: Capsule())
                if let kind = item?.sourceKind {
                    Text(kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                reliabilityBadge
                Spacer()
                if let date = item?.publishedAt {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(item?.title ?? label)
                .font(.headline)
                .lineLimit(3)
                .textSelection(.enabled)
            if let snippet = item?.snippet?.trimmingCharacters(in: .whitespacesAndNewlines), !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(6)
            } else if item == nil {
                Text("This citation isn't in the brief's source set — the model added it from context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let author = item?.author, !author.isEmpty {
                    Label(author, systemImage: "person")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link(destination: URL(string: urlString) ?? URL(string: "about:blank")!) {
                    Label("Open", systemImage: "arrow.up.right.square")
                        .font(.caption.bold())
                }
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private var host: String {
        URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }

    /// Source-kind tint/glyph for the host badge — consistent with the inline
    /// citation chips. Falls back to the accent color / no glyph when the
    /// citation isn't in the brief's source set.
    private var sourceTint: Color {
        item.map { SourcePalette.color(for: $0.sourceKind) } ?? .accentColor
    }

    private var sourceSymbol: String? {
        item.map { SourcePalette.symbol(for: $0.sourceKind) }
    }

    @ViewBuilder
    private var reliabilityBadge: some View {
        if let rel = state.reliability(for: host) {
            HStack(spacing: 3) {
                Image(systemName: rel.band == .ok ? "checkmark.seal.fill" :
                      rel.band == .mixed ? "questionmark.circle" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(rel.band.displayName)
                    .font(.caption2.bold())
            }
            .foregroundStyle(colorForBand(rel.band))
            .help("Host reliability: \(rel.score)/100 across \(rel.mentions) mentions")
        }
    }

    private func colorForBand(_ band: SourceReliability.Band) -> Color {
        switch band {
        case .ok:    return .green
        case .mixed: return .yellow
        case .watch: return .red
        }
    }
}
