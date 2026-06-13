import SwiftUI

/// The app's standard surface: a rounded, subtly filled container with an
/// optional titled `SectionHeader`. Visually matches the legacy card used in
/// the analytics dashboard (radius `Theme.Radius.card`, `cardFill`) so adopting
/// it is a no-op there, while giving every other view one consistent container.
///
/// - `accent`: when set, tints the header icon/title and switches the fill to a
///   faint wash of the accent — used by structured brief sections (V3).
/// - `elevated`: stronger fill + hairline border for cards that need to read as
///   "raised" (cluster cards, hovered surfaces).
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    var accent: Color?
    var elevated: Bool
    var padding: CGFloat
    @ViewBuilder var content: Content

    init(title: String? = nil,
         systemImage: String? = nil,
         accent: Color? = nil,
         elevated: Bool = false,
         padding: CGFloat = Theme.Spacing.md,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.elevated = elevated
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let title {
                SectionHeader(title, systemImage: systemImage, accent: accent)
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
    }

    private var fill: Color {
        if let accent { return accent.opacity(0.10) }
        return elevated ? Theme.Colors.cardFillElevated : Theme.Colors.cardFill
    }

    private var borderColor: Color {
        if let accent { return accent.opacity(0.28) }
        return elevated ? Theme.Colors.hairline : .clear
    }

    private var borderWidth: CGFloat {
        (accent != nil || elevated) ? 0.75 : 0
    }
}

#if DEBUG
#Preview("Card") {
    VStack(spacing: 16) {
        Card(title: "Plain card") {
            Text("Body content goes here.")
                .font(.callout)
        }
        Card(title: "Accented", systemImage: "sparkles", accent: .accentColor) {
            Text("A highlighted section.").font(.callout)
        }
        Card(title: "Elevated", systemImage: "square.stack", elevated: true) {
            Text("Raised surface.").font(.callout)
        }
    }
    .padding()
    .frame(width: 360)
}
#endif
