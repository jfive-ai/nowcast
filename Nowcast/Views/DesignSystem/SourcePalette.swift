import SwiftUI

/// Stable color + SF Symbol for each `SourceKind`, so a Hacker News link, an RSS
/// item, and a Reddit post are visually distinguishable at a glance wherever
/// sources are surfaced (citation chips V7, cluster chips V6, provenance,
/// analytics, source health). Colors are fixed saturated mid-tones chosen to
/// read on both light and dark backgrounds.
enum SourcePalette {
    static func color(for kind: SourceKind) -> Color {
        switch kind {
        case .hackerNews:     return Color(red: 1.00, green: 0.40, blue: 0.00)
        case .reddit:         return Color(red: 1.00, green: 0.27, blue: 0.00)
        case .youtubeSearch:  return Color(red: 0.90, green: 0.13, blue: 0.13)
        case .youtubeChannel: return Color(red: 0.72, green: 0.11, blue: 0.11)
        case .rss:            return Color(red: 0.93, green: 0.58, blue: 0.04)
        case .web:            return Color(red: 0.20, green: 0.48, blue: 0.95)
        case .news:           return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .xNitter:        return Color(red: 0.05, green: 0.62, blue: 0.69)
        }
    }

    static func symbol(for kind: SourceKind) -> String {
        switch kind {
        case .hackerNews:     return "y.square.fill"
        case .reddit:         return "bubble.left.and.bubble.right.fill"
        case .youtubeSearch:  return "play.rectangle.fill"
        case .youtubeChannel: return "play.rectangle.on.rectangle.fill"
        case .rss:            return "dot.radiowaves.up.forward"
        case .web:            return "globe"
        case .news:           return "newspaper.fill"
        case .xNitter:        return "at"
        }
    }

    /// Neutral fallback for links that don't resolve to a known source.
    static let unknownColor = Color.secondary
    static let unknownSymbol = "link"
}

#if DEBUG
#Preview("SourcePalette") {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(SourceKind.allCases) { kind in
            HStack(spacing: 8) {
                Image(systemName: SourcePalette.symbol(for: kind))
                    .foregroundStyle(SourcePalette.color(for: kind))
                    .frame(width: 22)
                Text(kind.displayName)
            }
        }
    }
    .padding()
    .frame(width: 280)
}
#endif
