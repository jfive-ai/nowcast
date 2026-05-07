import Foundation

/// YouTube Data API v3 search. Requires a Google API key with the YouTube
/// Data API enabled. Free tier is 10k quota units / day; each `search.list`
/// call costs 100 units, so this adapter caps at one call per fetch.
struct YouTubeSearchAdapter: SourceAdapter {
    let kind: SourceKind = .youtubeSearch

    private let session: URLSession
    private let apiKey: String

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetch(query: String,
               window: TimeWindow,
               subscriptions: [SourceSubscription]) async throws -> [RawItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !apiKey.isEmpty else { return [] }

        var c = URLComponents()
        c.scheme = "https"
        c.host = "www.googleapis.com"
        c.path = "/youtube/v3/search"
        c.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "order", value: "date"),
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "publishedAfter", value: Self.rfc3339(window.earliestDate)),
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = c.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SourceError.requestFailed(kind: .youtubeSearch)
        }

        let parsed = try JSONDecoder.youtube.decode(YTSearchResponse.self, from: data)
        return parsed.items.compactMap(Self.normalize)
    }

    static func normalize(_ item: YTSearchResponse.Item) -> RawItem? {
        guard let videoId = item.id.videoId,
              let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else { return nil }
        let snippet = item.snippet
        return RawItem(
            title: snippet.title,
            url: url,
            publishedAt: snippet.publishedAt,
            snippet: snippet.description,
            transcript: nil,
            sourceKind: .youtubeSearch,
            author: snippet.channelTitle
        )
    }

    private static func rfc3339(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    struct YTSearchResponse: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let id: ID
            let snippet: Snippet
        }
        struct ID: Decodable {
            let videoId: String?
        }
        struct Snippet: Decodable {
            let title: String
            let description: String
            let channelTitle: String
            let publishedAt: Date
        }
    }
}

extension JSONDecoder {
    /// YouTube returns ISO-8601 timestamps. Provide a shared decoder so all
    /// YouTube adapters parse them consistently.
    static let youtube: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: raw) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "Bad date: \(raw)")
        }
        return d
    }()
}
