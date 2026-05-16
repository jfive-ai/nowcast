import Foundation

/// Compares this run's clusters against the most-recent prior brief's
/// clusters on the same topic/preset and emits a `BriefDelta` describing
/// what's new, what's continuing, and what's dropped.
///
/// Similarity is intentionally embedding-free (P4-1 deferred embeddings):
/// case-folded Jaccard over alphanumeric word tokens of the headline +
/// summary. Threshold 0.30 — chosen so headline reflows ("ETH ETF flows
/// surge" vs "Surging ETH ETF flows") still match while genuinely new
/// stories don't.
enum BriefDiff {
    static let matchThreshold: Double = 0.30

    struct ContinuingPair: Equatable {
        let current: BriefingResult.Cluster
        let prior: BriefingResult.Cluster
    }

    struct BriefDelta: Equatable {
        var newClusters: [BriefingResult.Cluster] = []
        var continuingClusters: [ContinuingPair] = []
        var droppedClusters: [BriefingResult.Cluster] = []

        var isEmpty: Bool {
            newClusters.isEmpty && continuingClusters.isEmpty && droppedClusters.isEmpty
        }
    }

    static func diff(current: [BriefingResult.Cluster],
                     prior: [BriefingResult.Cluster]) -> BriefDelta {
        guard !prior.isEmpty else {
            return BriefDelta(newClusters: current)
        }

        var delta = BriefDelta()
        var usedPriorIndices = Set<Int>()

        for c in current {
            let cTokens = tokenize(c.headline + " " + c.summary)
            var bestIdx: Int?
            var bestScore = 0.0
            for (idx, p) in prior.enumerated() where !usedPriorIndices.contains(idx) {
                let pTokens = tokenize(p.headline + " " + p.summary)
                let score = jaccard(cTokens, pTokens)
                if score > bestScore {
                    bestScore = score
                    bestIdx = idx
                }
            }
            if let idx = bestIdx, bestScore >= matchThreshold {
                delta.continuingClusters.append(ContinuingPair(current: c, prior: prior[idx]))
                usedPriorIndices.insert(idx)
            } else {
                delta.newClusters.append(c)
            }
        }

        for (idx, p) in prior.enumerated() where !usedPriorIndices.contains(idx) {
            delta.droppedClusters.append(p)
        }
        return delta
    }

    static func renderMarkdown(_ delta: BriefDelta) -> String? {
        guard !delta.isEmpty else { return nil }
        var lines: [String] = ["## What's new since last brief"]
        if !delta.newClusters.isEmpty {
            for c in delta.newClusters {
                lines.append("- 🆕 **\(c.headline)**")
            }
        }
        if !delta.continuingClusters.isEmpty {
            for pair in delta.continuingClusters {
                if pair.current.headline.caseInsensitiveCompare(pair.prior.headline) == .orderedSame {
                    lines.append("- 🔁 **\(pair.current.headline)**")
                } else {
                    lines.append("- 🔁 **\(pair.current.headline)** — was: _\(pair.prior.headline)_")
                }
            }
        }
        if !delta.droppedClusters.isEmpty {
            for c in delta.droppedClusters {
                lines.append("- 💤 _No longer in view_ — \(c.headline)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func tokenize(_ s: String) -> Set<String> {
        let lowered = s.lowercased()
        let mapped: String = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }.reduce(into: "", { $0.append($1) })
        let stop: Set<String> = ["the","a","an","of","in","on","for","to","and","or","by","with","at","is","are","be","this","that"]
        return Set(mapped.split(separator: " ").map(String.init).filter {
            $0.count >= 3 && !stop.contains($0)
        })
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let inter = a.intersection(b).count
        let union = a.union(b).count
        return Double(inter) / Double(union)
    }
}
