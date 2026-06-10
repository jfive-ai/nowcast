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
    /// Discriminates daily briefs from synthesized weekly digests.
    /// Defaults to .daily for rows that pre-dated the v12 migration.
    var kind: Kind
    /// Optional LLM-generated headline summarizing the brief. Nil when
    /// the smart-titles toggle is off or the call failed; UI falls back
    /// to `topic`.
    var title: String?
    /// How strongly multiple sources converge on a single story.
    /// Higher = more "concentrated" agreement across sources. UI surfaces
    /// the top-15% per preset as a "big story" badge.
    var bigStoryScore: Double?
    /// Headline of the cluster that drove `bigStoryScore`. Used for
    /// tooltips on the History row and the ReportView banner.
    var bigStoryHeadline: String?
    /// LLM-reported overall tone of the *coverage* in [-1, +1].
    /// Nil for legacy briefs or providers that omitted the field.
    var sentiment: Double?
    /// One-line rationale shown on the trend chart hover and the
    /// in-report sentiment indicator.
    var sentimentRationale: String?

    /// What the UI should show: smart title when present, otherwise topic.
    var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? topic }

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
         kind: Kind = .daily,
         title: String? = nil,
         bigStoryScore: Double? = nil,
         bigStoryHeadline: String? = nil,
         sentiment: Double? = nil,
         sentimentRationale: String? = nil) {
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
        self.title = title
        self.bigStoryScore = bigStoryScore
        self.bigStoryHeadline = bigStoryHeadline
        self.sentiment = sentiment
        self.sentimentRationale = sentimentRationale
    }

    var isUnread: Bool { readAt == nil }

    var totalTokens: Int? {
        guard let p = promptTokens, let c = completionTokens else { return nil }
        return p + c
    }
}
