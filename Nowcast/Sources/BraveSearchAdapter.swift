import Foundation

/// General-purpose web search via the Brave Search API. Requires a user-
/// supplied API key (Settings → Brave Search). Brave's free tier is rate-
/// limited but usable; paid tiers unlock higher throughput.
///
/// Docs: https://api.search.brave.com/app/documentation/web-search
struct BraveSearchAdapter: SourceAdapter {
    let kind: SourceKind = .web

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
        c.host = "api.search.brave.com"
        c.path = "/res/v1/web/search"
        c.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "count", value: "20"),
            URLQueryItem(name: "freshness", value: Self.freshness(for: window)),
            URLQueryItem(name: "safesearch", value: "moderate"),
        ]
        guard let url = c.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SourceError.requestFailed(kind: .web)
        }

        let parsed = try JSONDecoder().decode(BraveResponse.self, from: data)
        let results = parsed.web?.results ?? []
        return results.compactMap { result -> RawItem? in
            guard let url = URL(string: result.url) else { return nil }
            return RawItem(
                title: result.title,
                url: url,
                publishedAt: nil,
                snippet: result.description,
                transcript: nil,
                sourceKind: .web,
                author: result.profile?.name
            )
        }
    }

    private static func freshness(for window: TimeWindow) -> String {
        switch window {
        case .lastHour, .today: return "pd"
        case .last7Days:        return "pw"
        }
    }

    private struct BraveResponse: Decodable {
        let web: WebBlock?
        struct WebBlock: Decodable {
            let results: [Result]?
        }
        struct Result: Decodable {
            let title: String
            let url: String
            let description: String?
            let profile: Profile?
        }
        struct Profile: Decodable {
            let name: String?
        }
    }
}
