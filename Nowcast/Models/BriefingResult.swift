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

        // FIX (codex review PR #27): `id` is decoded as optional and
        // synthesized when the model omits it. `saveBriefing` always
        // generates a fresh UUID anyway, so the decoded `id` only matters
        // for in-memory traversal — failing the whole payload because of
        // a missing `id` discarded an otherwise-usable brief.
        private enum CodingKeys: String, CodingKey {
            case id, headline, summary, claims, citations
        }

        init(id: String, headline: String, summary: String, claims: [Claim], citations: [String]) {
            self.id = id
            self.headline = headline
            self.summary = summary
            self.claims = claims
            self.citations = citations
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
            self.headline = try c.decode(String.self, forKey: .headline)
            self.summary = try c.decode(String.self, forKey: .summary)
            self.claims = (try? c.decodeIfPresent([Claim].self, forKey: .claims)) ?? []
            self.citations = (try? c.decodeIfPresent([String].self, forKey: .citations)) ?? []
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
