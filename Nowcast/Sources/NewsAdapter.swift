import Foundation
import FeedKit

/// News via Google News RSS search. Free, no key, but Google may rotate
/// formats — keep parsing defensive.
///
/// Endpoint shape:
///   https://news.google.com/rss/search?q=<query>+when:<window>&hl=<locale>
///
/// Items returned are RSS 2.0; titles tend to embed the publisher name as
/// " - Publisher", which we surface as the `author` field.
struct NewsAdapter: SourceAdapter {
    let kind: SourceKind = .news

    private let session: URLSession
    private let locale: String

    init(session: URLSession = .shared, locale: String = "en-US") {
        self.session = session
        self.locale = locale
    }

    func fetch(query: String,
               window: TimeWindow,
               subscriptions: [SourceSubscription]) async throws -> [RawItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        guard let url = makeURL(query: trimmed, window: window) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Nowcast/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SourceError.requestFailed(kind: .news)
        }

        let feed = try await Self.parseRSS(data: data)
        let cutoff = window.earliestDate

        return (feed.items ?? []).compactMap { entry -> RawItem? in
            guard let rawTitle = entry.title?.nonEmpty,
                  let link = entry.link.flatMap(URL.init(string:)) else { return nil }
            if let published = entry.pubDate, published < cutoff { return nil }

            let (cleanTitle, publisher) = Self.splitPublisher(from: rawTitle)
            return RawItem(
                title: cleanTitle,
                url: link,
                publishedAt: entry.pubDate,
                snippet: entry.description?.nonEmpty,
                transcript: nil,
                sourceKind: .news,
                author: publisher ?? entry.source?.value
            )
        }
    }

    private func makeURL(query: String, window: TimeWindow) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "news.google.com"
        c.path = "/rss/search"
        // The `when:` operator inside `q` is what Google News honors most
        // reliably for time-windowed search.
        let scopedQuery = "\(query) when:\(Self.googleNewsWhen(for: window))"
        c.queryItems = [
            URLQueryItem(name: "q", value: scopedQuery),
            URLQueryItem(name: "hl", value: locale),
            URLQueryItem(name: "gl", value: Self.region(from: locale)),
            URLQueryItem(name: "ceid", value: "\(Self.region(from: locale)):\(Self.lang(from: locale))"),
        ]
        return c.url
    }

    private static func googleNewsWhen(for window: TimeWindow) -> String {
        switch window {
        case .lastHour:  return "1h"
        case .today:     return "1d"
        case .last7Days: return "7d"
        }
    }

    private static func region(from locale: String) -> String {
        let parts = locale.split(separator: "-")
        return parts.count == 2 ? String(parts[1]) : "US"
    }

    private static func lang(from locale: String) -> String {
        let parts = locale.split(separator: "-")
        return parts.first.map(String.init) ?? "en"
    }

    /// Google News titles look like "Headline - Publisher". Split on the
    /// final " - " so we can record the publisher as the author.
    private static func splitPublisher(from title: String) -> (String, String?) {
        guard let range = title.range(of: " - ", options: .backwards) else {
            return (title, nil)
        }
        let head = String(title[..<range.lowerBound])
        let tail = String(title[range.upperBound...])
        return (head, tail.isEmpty ? nil : tail)
    }

    private static func parseRSS(data: Data) async throws -> RSSFeed {
        let feed: Feed = try await withCheckedThrowingContinuation { cont in
            FeedParser(data: data).parseAsync { result in
                switch result {
                case .success(let f): cont.resume(returning: f)
                case .failure(let e): cont.resume(throwing: e)
                }
            }
        }
        guard case .rss(let rss) = feed else {
            throw SourceError.requestFailed(kind: .news)
        }
        return rss
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
