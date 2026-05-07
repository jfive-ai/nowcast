import Foundation

struct Report: Identifiable, Codable, Hashable {
    let id: UUID
    let presetID: UUID?
    let topic: String
    let window: TimeWindow
    let generatedAt: Date
    /// Path to the markdown file relative to the reports root.
    let markdownPath: String
    let byteSize: Int64
    let sourceCount: Int
    /// `nil` while unread; set when the user opens the report.
    var readAt: Date?
    /// Recorded LLM usage when available. All `nil` for reports created
    /// before the v3 schema migration or by providers that don't report
    /// token counts.
    let promptTokens: Int?
    let completionTokens: Int?
    /// Approximate USD cost computed via `ModelPricing` at generation time.
    /// Stored verbatim so the value doesn't drift if pricing changes later.
    let usdCost: Double?
    let modelUsed: String?
    let providerUsed: String?

    var isUnread: Bool { readAt == nil }

    var totalTokens: Int? {
        guard let p = promptTokens, let c = completionTokens else { return nil }
        return p + c
    }
}
