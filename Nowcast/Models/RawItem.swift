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

    /// Stable hash of the URL — used for `seen_item` dedup so the same story
    /// isn't summarized twice across runs.
    var urlHash: String {
        url.absoluteString.lowercased()
    }
}
