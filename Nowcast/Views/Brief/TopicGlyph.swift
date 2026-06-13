import SwiftUI

/// Deterministic SF Symbol + tint for a topic string, so a given topic always
/// gets the same visual identity (header glyph V4, history accent V8). Uses a
/// stable (launch-independent) hash — `String.hashValue` is randomized per
/// process and would change the glyph every relaunch.
enum TopicGlyph {
    private static let symbols = [
        "bolt.fill", "flame.fill", "leaf.fill", "globe.americas.fill",
        "cpu", "chart.line.uptrend.xyaxis", "building.2.fill", "brain.head.profile",
        "sparkles", "newspaper.fill", "atom", "network",
        "bitcoinsign.circle.fill", "shield.lefthalf.filled", "wand.and.stars", "scope",
    ]
    private static let tints: [Color] = [
        .blue, .purple, .teal, .orange, .pink, .indigo, .green, .red, .cyan, .mint,
    ]

    static func symbol(for topic: String) -> String {
        symbols[Int(hash(topic) % UInt64(symbols.count))]
    }

    static func tint(for topic: String) -> Color {
        tints[Int((hash(topic) / 7) % UInt64(tints.count))]
    }

    /// FNV-ish stable hash over the topic's UTF-8 bytes; same input → same value
    /// across launches and machines.
    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.lowercased().utf8 {
            h = (h &* 33) ^ UInt64(b)
        }
        return h & 0x7fff_ffff_ffff_ffff
    }
}
