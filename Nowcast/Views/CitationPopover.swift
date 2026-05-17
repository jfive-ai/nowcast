import SwiftUI

/// Popover body shown when the user hovers a citation chip in
/// `MarkdownLinkText` (P6-1). Surfaces the matched `PersistedItem` if one
/// exists in the brief's source set; otherwise a minimal preview of just
/// the URL host.
struct CitationPopover: View {
    let label: String
    let urlString: String
    let item: PersistedItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(host)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(Capsule())
                if let kind = item?.sourceKind {
                    Text(kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
}
