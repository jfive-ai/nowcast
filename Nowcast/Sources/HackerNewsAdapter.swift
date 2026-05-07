import Foundation

/// Algolia HN search API — free, no key. Docs: https://hn.algolia.com/api
struct HackerNewsAdapter: SourceAdapter {
    let kind: SourceKind = .hackerNews

    private let session: URLSession
    private let isoFormatter: ISO8601DateFormatter

    init(session: URLSession = .shared) {
        self.session = session
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = f
    }

    func fetch(query: String,
               window: TimeWindow,
               subscriptions: [SourceSubscription]) async throws -> [RawItem] {
        var components = URLComponents(string: "https://hn.algolia.com/api/v1/search_by_date")!
        let unix = Int(window.earliestDate.timeIntervalSince1970)
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "tags", value: "story"),
            URLQueryItem(name: "numericFilters", value: "created_at_i>\(unix)"),
            URLQueryItem(name: "hitsPerPage", value: "30"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SourceError.requestFailed(kind: .hackerNews)
        }
        let parsed = try JSONDecoder().decode(HNResponse.self, from: data)

        return parsed.hits.compactMap { hit in
            let title = hit.title ?? hit.story_title
            let urlString = hit.url ?? hit.story_url
                ?? "https://news.ycombinator.com/item?id=\(hit.objectID)"
            guard let title, let resolvedURL = URL(string: urlString) else { return nil }

            let published: Date? = isoFormatter.date(from: hit.created_at)
                ?? Self.fallbackParse(hit.created_at)

            return RawItem(
                title: title,
                url: resolvedURL,
                publishedAt: published,
                snippet: hit.story_text ?? hit.comment_text,
                transcript: nil,
                sourceKind: .hackerNews,
                author: hit.author
            )
        }
    }

    /// HN sometimes returns timestamps without fractional seconds.
    private static func fallbackParse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private struct HNResponse: Decodable {
        let hits: [HNHit]
    }

    private struct HNHit: Decodable {
        let objectID: String
        let title: String?
        let story_title: String?
        let url: String?
        let story_url: String?
        let story_text: String?
        let comment_text: String?
        let created_at: String
        let author: String?
    }
}

enum SourceError: Error, LocalizedError {
    case requestFailed(kind: SourceKind)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let kind):
            return "\(kind.displayName) request failed."
        }
    }
}
