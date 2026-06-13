import SwiftUI

/// A compact "at a glance" strip under the header: the shape of the result in a
/// glance — how many stories, how many items, and roughly how long it reads.
struct StatStrip: View {
    let storyCount: Int
    let itemCount: Int
    let readMinutes: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            stat(value: "\(storyCount)",
                 label: storyCount == 1 ? "story" : "stories",
                 systemImage: "newspaper.fill",
                 tint: .indigo)
            divider
            stat(value: "\(itemCount)",
                 label: itemCount == 1 ? "item" : "items",
                 systemImage: "tray.full.fill",
                 tint: .teal)
            divider
            stat(value: "~\(readMinutes)",
                 label: "min read",
                 systemImage: "book.fill",
                 tint: .orange)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(width: 1, height: 22)
    }

    private func stat(value: String, label: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            HStack(spacing: 3) {
                Text(value).font(.callout.bold())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview("StatStrip") {
    StatStrip(storyCount: 3, itemCount: 14, readMinutes: 2)
        .padding()
        .frame(width: 460)
}
#endif
