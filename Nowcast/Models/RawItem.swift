import Foundation

/// A single piece of source content normalized across all adapters before
/// being merged, deduped, and sent to the LLM.
struct RawItem: Hashable, Codable {
    let title: String
    let url: URL
    let publishedAt: Date?
    let snippet: String?
    let transcript: String?
    let sourceKind: SourceKind
    let author: String?

    /// Stable hash of the canonicalized URL — used for `seen_item` dedup so
    /// the same story isn't summarized twice across runs even when the URL
    /// differs by trailing slash, tracker params, mobile-prefix host, etc.
    var urlHash: String {
        URLCanonicalizer.hash(url)
    }
}
