import SwiftUI

/// A placeholder shown while a report's markdown loads from disk, sized to echo
/// the real layout (header glyph + title, stat strip, a few section cards) so
/// the content doesn't pop in from blank. Gently pulses; respects Reduce Motion.
struct ReportSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var barOpacity: Double {
        if reduceMotion { return 0.6 }
        return pulsing ? 0.9 : 0.4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                bar(width: 44, height: 44, radius: Theme.Radius.card)
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    bar(width: 220, height: 22)
                    bar(width: 150, height: 12)
                }
            }
            bar(height: 40, radius: Theme.Radius.card)
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    bar(width: 120, height: 14)
                    bar(height: 10)
                    bar(height: 10)
                    bar(width: 240, height: 10)
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
            }
        }
        .padding(24)
        .frame(maxWidth: Theme.Layout.readingMeasure, alignment: .leading)
        .frame(maxWidth: .infinity)
        .opacity(barOpacity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityLabel("Loading briefing")
    }

    @ViewBuilder
    private func bar(width: CGFloat? = nil, height: CGFloat, radius: CGFloat = 5) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.secondary.opacity(0.22))
        if let width {
            shape.frame(width: width, height: height)
        } else {
            shape.frame(maxWidth: .infinity).frame(height: height)
        }
    }
}

#if DEBUG
#Preview("ReportSkeletonView") {
    ReportSkeletonView()
        .frame(width: 560, height: 600)
}
#endif
