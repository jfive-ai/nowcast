import Foundation

/// Computes a single "how concentrated is this brief?" score from a
/// `BriefingResult`. The intuition: when many independent sources
/// converge on the same story, *that's* what reporters call "the story" —
/// and that's what should jump out of the History list at a glance.
///
/// Score = `max distinct source-host count in any single cluster`
///       + `0.5 * (clusters with 3+ source hosts)`
///
/// "Sources" are URL hosts extracted from cluster citations, not adapter
/// kinds — two HN + two Reddit links to the same story still counts as
/// four distinct sources.
enum BigStoryScorer {
    struct Outcome {
        let score: Double
        /// Headline of the cluster that produced the max source-host count.
        /// Used by the UI for tooltip / banner copy.
        let headline: String?
    }

    static func score(_ result: BriefingResult) -> Outcome {
        guard !result.clusters.isEmpty else {
            return Outcome(score: 0, headline: nil)
        }

        var maxHosts = 0
        var topHeadline: String? = nil
        var clustersWith3PlusHosts = 0

        for cluster in result.clusters {
            let hosts = uniqueHosts(for: cluster)
            if hosts.count >= 3 { clustersWith3PlusHosts += 1 }
            if hosts.count > maxHosts {
                maxHosts = hosts.count
                topHeadline = cluster.headline
            }
        }

        let score = Double(maxHosts) + 0.5 * Double(clustersWith3PlusHosts)
        return Outcome(score: score, headline: topHeadline)
    }

    /// Distinct lower-cased hosts cited by a cluster. Strips `www.` so
    /// `www.nytimes.com` and `nytimes.com` count once.
    private static func uniqueHosts(for cluster: BriefingResult.Cluster) -> Set<String> {
        let citations = cluster.citations + cluster.claims.flatMap(\.citations)
        var hosts = Set<String>()
        for citation in citations {
            guard var host = URL(string: citation)?.host?.lowercased() else { continue }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            hosts.insert(host)
        }
        return hosts
    }

    /// True when `score` is in the top ~15% of the comparison set, OR (for
    /// young presets with <10 data points) clears the absolute floor.
    /// The percentile is a cheap nearest-rank: sort, peek at the 85th-%ile.
    static func isBig(score: Double,
                      comparison priorScores: [Double],
                      absoluteFloor: Double = 5.0) -> Bool {
        guard score > 0 else { return false }
        if priorScores.count < 10 {
            return score >= absoluteFloor
        }
        let sorted = priorScores.sorted()
        let idx = Int(Double(sorted.count - 1) * 0.85)
        let threshold = sorted[idx]
        return score >= threshold
    }
}
