import SwiftUI

/// A compact labeled capsule for metadata and citations: optional leading SF
/// Symbol + text, tinted by `tint` (defaults to a neutral secondary). Used for
/// the header metadata row (V4), citation chips (V7), and history tone chips (V8).
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color?

    init(_ text: String, systemImage: String? = nil, tint: Color? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(tint ?? .secondary)
        .background((tint ?? Color.secondary).opacity(0.14), in: Capsule())
        .overlay(
            Capsule().strokeBorder((tint ?? Color.secondary).opacity(0.22), lineWidth: 0.5)
        )
    }
}

#if DEBUG
#Preview("Chip") {
    HStack {
        Chip("24h window", systemImage: "clock")
        Chip("14 items", systemImage: "tray.full")
        Chip("Bullish", systemImage: "arrow.up.right", tint: .green)
        Chip("$0.01", systemImage: "dollarsign.circle", tint: .accentColor)
    }
    .padding()
}
#endif
