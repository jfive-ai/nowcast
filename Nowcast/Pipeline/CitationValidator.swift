import Foundation

/// Drops any citation URL in a `BriefingResult` that isn't present in the
/// model's input set. Empty clusters (every citation invalid) are removed.
/// This is the cheap guard against the LLM fabricating links.
enum CitationValidator {
    static func filter(_ result: BriefingResult, againstInputs inputs: [RawItem]) -> BriefingResult {
        let validHashes = Set(inputs.map(\.urlHash))

        let filteredClusters = result.clusters.compactMap { cluster -> BriefingResult.Cluster? in
            let keptCitations = cluster.citations.filter { isValid($0, validHashes: validHashes) }
            let keptClaims = cluster.claims.map { claim in
                BriefingResult.Claim(
                    text: claim.text,
                    citations: claim.citations.filter { isValid($0, validHashes: validHashes) }
                )
            }
            // Drop a cluster only if it ends up with zero valid citations AND
            // none of its claims has any valid citation either — anything
            // less aggressive risks silently dropping good content.
            let hasAnyValidCitation = !keptCitations.isEmpty
                || keptClaims.contains(where: { !$0.citations.isEmpty })
            guard hasAnyValidCitation else { return nil }

            return BriefingResult.Cluster(
                id: cluster.id,
                headline: cluster.headline,
                summary: cluster.summary,
                claims: keptClaims,
                citations: keptCitations
            )
        }

        return BriefingResult(
            tldr: result.tldr,
            clusters: filteredClusters,
            signal: result.signal,
            lowConfidence: result.lowConfidence || filteredClusters.count < result.clusters.count
        )
    }

    private static func isValid(_ raw: String, validHashes: Set<String>) -> Bool {
        guard let url = URL(string: raw) else { return false }
        return validHashes.contains(URLCanonicalizer.hash(url))
    }
}
