import SwiftUI

/// Coverage-tone indicator: a segmented red→neutral→green gradient gauge with a
/// marker at the value, a tinted tone label, and the rationale inline. Replaces
/// the old 4pt gray capsule + tiny dot. The trend affordance is shown only when
/// `onTrend` is provided (i.e. the report belongs to a preset).
struct SentimentGauge: View {
    let sentiment: Double
    var rationale: String?
    var onTrend: (() -> Void)?

    private var clamped: Double { max(-1, min(1, sentiment)) }
    private var pct: Double { (clamped + 1) / 2 }

    private var label: String {
        if clamped > 0.25 { return "Bullish" }
        if clamped < -0.25 { return "Bearish" }
        return "Neutral"
    }

    private var tint: Color {
        if clamped > 0.25 { return .green }
        if clamped < -0.25 { return .red }
        return .secondary
    }

    private var icon: String {
        if clamped > 0.25 { return "arrow.up.right" }
        if clamped < -0.25 { return "arrow.down.right" }
        return "arrow.left.and.right"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon).font(.caption).foregroundStyle(tint)
                Text("Coverage tone").font(.caption).foregroundStyle(.secondary)
                Text(label).font(.caption.bold()).foregroundStyle(tint)
                Text(String(format: "%+.1f", clamped))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let onTrend {
                    Button(action: onTrend) {
                        Label("Trend", systemImage: "chart.line.uptrend.xyaxis")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Show coverage-tone trend for this topic")
                }
            }
            gauge
            if let rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coverage tone: \(label), \(String(format: "%+.1f", clamped))")
    }

    private var gauge: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let trackY = geo.size.height / 2
            let markerX = max(8, min(w - 8, w * pct))
            ZStack {
                Capsule()
                    .fill(LinearGradient(
                        colors: [.red, Color.gray.opacity(0.40), .green],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: w, height: 6)
                    .position(x: w / 2, y: trackY)
                // Neutral center tick.
                Rectangle()
                    .fill(Color.primary.opacity(0.28))
                    .frame(width: 1.5, height: 12)
                    .position(x: w / 2, y: trackY)
                // Value marker.
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(Circle().strokeBorder(tint, lineWidth: 3))
                    .frame(width: 15, height: 15)
                    .position(x: markerX, y: trackY)
            }
        }
        .frame(height: 16)
    }
}

#if DEBUG
#Preview("SentimentGauge") {
    VStack(spacing: 12) {
        SentimentGauge(sentiment: 0.6, rationale: "Strong inflows and bullish ETF coverage.", onTrend: {})
        SentimentGauge(sentiment: 0.0, rationale: "Mixed, procedural coverage.", onTrend: {})
        SentimentGauge(sentiment: -0.7, rationale: "Record outflows dominate the narrative.", onTrend: nil)
    }
    .padding()
    .frame(width: 420)
}
#endif
