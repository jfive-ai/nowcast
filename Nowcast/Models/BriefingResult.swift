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

    struct Cluster: Codable, Equatable, Identifiable {
        let id: String
        let headline: String
        let summary: String
        let claims: [Claim]
        let citations: [String]
        /// P5-3: optional steel-manned counter-argument for the cluster's
        /// dominant framing. `nil` when the agent declined to invent one.
        var counterpoint: String?
        /// P5-3: optional "what this brief doesn't cover" note — a short
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
        case tldr, clusters, signal, lowConfidence = "low_confidence"
    }
}
