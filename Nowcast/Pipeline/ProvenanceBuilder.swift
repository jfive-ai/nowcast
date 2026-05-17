import Foundation

/// Pure mapper from the structured clusters + persisted items of a report
/// into a flat list of (cluster, claim, supporting items) rows (P6-2).
/// Used by `ProvenanceView` to render the "show your work" panel.
enum ProvenanceBuilder {
    struct ClusterRows: Identifiable {
        let clusterID: String
        let headline: String
        var rows: [ClaimRow]

        var id: String { clusterID }
    }

    struct ClaimRow: Identifiable {
        let id = UUID()
        let claim: BriefingResult.Claim
        let supportingItems: [PersistedItem]
        let unmatchedCitations: [String]
    }

    /// Build the panel rows. Citations are matched against items by
    /// canonical-URL substring — same approach `BriefChatSession` and
    /// `MarkdownLinkText` use, so coverage stays consistent.
    static func build(clusters: [BriefingResult.Cluster],
                      items: [PersistedItem]) -> [ClusterRows] {
        let urlIndex = MarkdownLinkText.buildIndex(items: items)
        let itemByCanon = items.reduce(into: [String: PersistedItem]()) { acc, item in
            acc[item.canonicalURL.absoluteString.lowercased()] = item
        }

        return clusters.map { cluster -> ClusterRows in
            // If the cluster has explicit per-claim citations we use them;
            // otherwise we fall back to the cluster-level `citations`.
            let perClaim: [ClaimRow] = cluster.claims.map { claim -> ClaimRow in
                let cites = claim.citations.isEmpty ? cluster.citations : claim.citations
                let resolved = Self.resolve(cites, urlIndex: urlIndex, byCanon: itemByCanon)
                return ClaimRow(claim: claim, supportingItems: resolved.matched, unmatchedCitations: resolved.unmatched)
            }

            // Synthesize a fake "summary claim" row when the cluster has
            // no structured claims at all, so the panel still shows the
            // cluster's sourcing.
            let rows: [ClaimRow]
            if perClaim.isEmpty {
                let resolved = Self.resolve(cluster.citations, urlIndex: urlIndex, byCanon: itemByCanon)
                rows = [ClaimRow(
                    claim: BriefingResult.Claim(text: cluster.summary, citations: cluster.citations),
                    supportingItems: resolved.matched,
                    unmatchedCitations: resolved.unmatched
                )]
            } else {
                rows = perClaim
            }

            return ClusterRows(clusterID: cluster.id, headline: cluster.headline, rows: rows)
        }
    }

    /// Split a list of citation URLs into matched items + unmatched strings.
    static func resolve(_ citations: [String],
                        urlIndex: [String: PersistedItem],
                        byCanon: [String: PersistedItem]) -> (matched: [PersistedItem], unmatched: [String]) {
        var matched: [PersistedItem] = []
        var unmatched: [String] = []
        var seen: Set<UUID> = []
        for raw in citations {
            let norm = MarkdownLinkText.normalize(raw)
            if let item = urlIndex[norm] ?? byCanon[raw.lowercased()] {
                if seen.insert(item.id).inserted { matched.append(item) }
            } else {
                unmatched.append(raw)
            }
        }
        return (matched, unmatched)
    }
}
