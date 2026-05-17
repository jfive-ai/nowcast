import Foundation

struct Report: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case daily
        case weeklyDigest

        var displayName: String {
            switch self {
            case .daily:        return "Brief"
            case .weeklyDigest: return "Weekly digest"
            }
        }
    }

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
    /// Discriminates daily briefs from synthesized weekly digests (P5-6).
    /// Defaults to .daily for rows that pre-dated the v12 migration.
    var kind: Kind

    init(id: UUID,
         presetID: UUID?,
         topic: String,
         window: TimeWindow,
         generatedAt: Date,
         markdownPath: String,
         byteSize: Int64,
         sourceCount: Int,
         readAt: Date? = nil,
         promptTokens: Int? = nil,
         completionTokens: Int? = nil,
         usdCost: Double? = nil,
         modelUsed: String? = nil,
         providerUsed: String? = nil,
         kind: Kind = .daily) {
        self.id = id
        self.presetID = presetID
        self.topic = topic
        self.window = window
        self.generatedAt = generatedAt
        self.markdownPath = markdownPath
        self.byteSize = byteSize
        self.sourceCount = sourceCount
        self.readAt = readAt
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.usdCost = usdCost
        self.modelUsed = modelUsed
        self.providerUsed = providerUsed
        self.kind = kind
    }

    var isUnread: Bool { readAt == nil }

    var totalTokens: Int? {
        guard let p = promptTokens, let c = completionTokens else { return nil }
        return p + c
    }
}
