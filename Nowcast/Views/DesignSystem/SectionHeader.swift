import SwiftUI

/// A titled header for a card or section: optional leading SF Symbol (tinted by
/// `accent`) + a headline title. With no symbol it degrades to a plain headline
/// so it can stand in for ad-hoc `Text(title).font(.headline)` usage.
struct SectionHeader: View {
    let title: String
    var systemImage: String?
    var accent: Color?
    var trailingText: String?

    init(_ title: String,
         systemImage: String? = nil,
         accent: Color? = nil,
         trailingText: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.trailingText = trailingText
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(accent ?? .secondary)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(accent ?? .primary)
            Spacer(minLength: 0)
            if let trailingText {
                Text(trailingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: 12) {
        SectionHeader("Plain title")
        SectionHeader("With icon", systemImage: "sparkles", accent: .accentColor)
        SectionHeader("With trailing", systemImage: "clock", accent: .orange, trailingText: "3 items")
    }
    .padding()
    .frame(width: 320)
}
#endif
