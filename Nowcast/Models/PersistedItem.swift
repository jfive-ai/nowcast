import Foundation

/// An item persisted to the `item` table. Mirrors `RawItem` but carries an
/// identity (`id`) and a normalized `canonicalURL`, so the same story across
/// runs collapses into one row.
struct PersistedItem: Hashable, Codable, Identifiable {
    let id: UUID
    let canonicalURL: URL
    let urlHash: String
    let title: String
    let snippet: String?
    let transcript: String?
    let sourceKind: SourceKind
    let author: String?
    let publishedAt: Date?
    let firstSeenAt: Date

    init(from raw: RawItem, firstSeenAt: Date = Date()) {
        let canon = URLCanonicalizer.canonicalize(raw.url)
        self.id = UUID()
        self.canonicalURL = canon
        self.urlHash = URLCanonicalizer.hash(raw.url)
        self.title = raw.title
        self.snippet = raw.snippet
        self.transcript = raw.transcript
        self.sourceKind = raw.sourceKind
        self.author = raw.author
        self.publishedAt = raw.publishedAt
        self.firstSeenAt = firstSeenAt
    }

    init(id: UUID,
         canonicalURL: URL,
         urlHash: String,
         title: String,
         snippet: String?,
         transcript: String?,
         sourceKind: SourceKind,
         author: String?,
         publishedAt: Date?,
         firstSeenAt: Date) {
        self.id = id
        self.canonicalURL = canonicalURL
        self.urlHash = urlHash
        self.title = title
        self.snippet = snippet
        self.transcript = transcript
        self.sourceKind = sourceKind
        self.author = author
        self.publishedAt = publishedAt
        self.firstSeenAt = firstSeenAt
    }
}
