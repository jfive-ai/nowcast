import Foundation

/// Machine-readable structure the LLM is asked to emit alongside its
/// human-facing markdown. Lets us persist clusters and claims to the DB
/// (powering diff, search, contradiction detection, source-trust) without
/// reparsing free-form markdown.
struct BriefingResult: Codable, Equatable {
    let tldr: [String]
    var clusters: [Cluster]
    let signal: String
    let lowConfidence: Bool
    /// Overall tone of the *coverage* in [-1.0, +1.0]. Negative =
    /// bearish/critical/alarmed; neutral = mixed/procedural; positive =
    /// bullish/optimistic. Nil for legacy responses where the model
    /// omitted the field — UI just skips that data point.
    var sentiment: Double?
    /// One-sentence "why this number" for tooltips on the trend chart.
    var sentimentRationale: String?

    struct Cluster: Codable, Equatable, Identifiable {
        let id: String
        let headline: String
        let summary: String
        let claims: [Claim]
        let citations: [String]
        /// Optional steel-manned counter-argument for the cluster's
        /// dominant framing. `nil` when the agent declined to invent one.
        var counterpoint: String?
        /// Optional "what this brief doesn't cover" note — a short
        /// pointer at the missing context.
        var gap: String?

        init(id: String,
             headline: String,
             summary: String,
             claims: [Claim],
             citations: [String],
             counterpoint: String? = nil,
             gap: String? = nil) {
            self.id = id
            self.headline = headline
            self.summary = summary
            self.claims = claims
            self.citations = citations
            self.counterpoint = counterpoint
            self.gap = gap
        }
    }

    struct Claim: Codable, Equatable {
        let text: String
        let citations: [String]
    }

    private enum CodingKeys: String, CodingKey {
        case tldr, clusters, signal
        case lowConfidence = "low_confidence"
        case sentiment
        case sentimentRationale = "sentiment_rationale"
    }

    init(tldr: [String],
         clusters: [Cluster],
         signal: String,
         lowConfidence: Bool,
         sentiment: Double? = nil,
         sentimentRationale: String? = nil) {
        self.tldr = tldr
        self.clusters = clusters
        self.signal = signal
        self.lowConfidence = lowConfidence
        self.sentiment = Self.clamp(sentiment)
        self.sentimentRationale = sentimentRationale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tldr = try c.decode([String].self, forKey: .tldr)
        self.clusters = try c.decode([Cluster].self, forKey: .clusters)
        self.signal = try c.decode(String.self, forKey: .signal)
        self.lowConfidence = try c.decode(Bool.self, forKey: .lowConfidence)
        let rawSentiment = try c.decodeIfPresent(Double.self, forKey: .sentiment)
        self.sentiment = Self.clamp(rawSentiment)
        self.sentimentRationale = try c.decodeIfPresent(String.self, forKey: .sentimentRationale)
    }

    /// Pin LLM-reported sentiment to [-1, +1] — defensive against models
    /// that occasionally drift to 5 or 100 instead of 0.5.
    private static func clamp(_ value: Double?) -> Double? {
        value.map { max(-1, min(1, $0)) }
    }
}
