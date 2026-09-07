import Foundation

func cluster(_ id: String = "c1", headline: String = "A story", summary: String = "", citations: [String] = [], claims: [BriefingResult.Claim] = []) -> BriefingResult.Cluster {
    .init(id: id, headline: headline, summary: summary, claims: claims, citations: citations)
}
func brief(_ clusters: [BriefingResult.Cluster]) -> BriefingResult {
    .init(tldr: [], clusters: clusters, signal: "", lowConfidence: false)
}
