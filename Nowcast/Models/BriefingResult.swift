import Foundation

/// Machine-readable structure the LLM is asked to emit alongside its
/// human-facing markdown. Lets us persist clusters and claims to the DB
/// (powering diff, search, contradiction detection, source-trust) without
/// reparsing free-form markdown.
struct BriefingResult: Codable, Equatable {
    let tldr: [String]
    let clusters: [Cluster]
    let signal: String
    let lowConfidence: Bool

    struct Cluster: Codable, Equatable, Identifiable {
        let id: String
        let headline: String
        let summary: String
        let claims: [Claim]
        let citations: [String]
    }

    struct Claim: Codable, Equatable {
        let text: String
        let citations: [String]
    }

    private enum CodingKeys: String, CodingKey {
        case tldr, clusters, signal, lowConfidence = "low_confidence"
    }
}
