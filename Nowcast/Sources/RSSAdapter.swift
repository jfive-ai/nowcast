import Foundation
import FeedKit

/// Pulls items from arbitrary RSS / Atom / JSON feeds the user has
/// subscribed to. RSS is subscription-only — there is no "search all RSS"
/// concept, so an empty subscription list yields no items.
struct RSSAdapter: SourceAdapter {
    let kind: SourceKind = .rss

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(query: String,
               window: TimeWindow,
               subscriptions: [SourceSubscription]) async throws -> [RawItem] {
        let feeds = subscriptions
            .filter { $0.kind == .rss }
            .compactMap { sub -> URL? in URL(string: sub.identifier) }
        guard !feeds.isEmpty else { return [] }

        let cutoff = window.earliestDate
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces).lowercased()

        return try await withThrowingTaskGroup(of: [RawItem].self) { group in
            for url in feeds {
                group.addTask {
                    do {
                        return try await fetchFeed(url: url, cutoff: cutoff, query: trimmedQuery)
                    } catch {
                        // One bad feed shouldn't fail the whole report.
                        return []
                    }
                }
            }
            var all: [RawItem] = []
            for try await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    // MARK: - Internals

    private func fetchFeed(url: URL, cutoff: Date, query: String) async throws -> [RawItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Nowcast/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SourceError.requestFailed(kind: .rss)
        }

        let result = try await Self.parse(data: data)
        let items: [RawItem]
        switch result {
        case .rss(let rss):    items = Self.normalize(rss)
        case .atom(let atom):  items = Self.normalize(atom)
        case .json(let json):  items = Self.normalize(json)
        }

        return items.filter { item in
            guard let published = item.publishedAt else { return true }
            guard published >= cutoff else { return false }
            // RSS feeds aren't searchable server-side — apply a loose
            // client-side keyword filter so a topic-scoped briefing
            // doesn't drown in unrelated entries from a general feed.
            return query.isEmpty || Self.matchesQuery(item, query: query)
        }
    }

    /// Wrap FeedKit's closure API in async/await.
    private static func parse(data: Data) async throws -> Feed {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Feed, Error>) in
            let parser = FeedParser(data: data)
            parser.parseAsync { result in
                switch result {
                case .success(let feed):
                    cont.resume(returning: feed)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func matchesQuery(_ item: RawItem, query: String) -> Bool {
        let title = item.title.lowercased()
        let snippet = item.snippet?.lowercased() ?? ""
        return title.contains(query) || snippet.contains(query)
    }

    // MARK: - Normalization

    private static func normalize(_ feed: RSSFeed) -> [RawItem] {
        (feed.items ?? []).compactMap { entry -> RawItem? in
            guard let title = entry.title?.nonEmpty,
                  let link = entry.link.flatMap(URL.init(string:)) else { return nil }
            return RawItem(
                title: title,
                url: link,
                publishedAt: entry.pubDate,
                snippet: entry.description?.nonEmpty,
                transcript: nil,
                sourceKind: .rss,
                author: entry.author
            )
        }
    }

    private static func normalize(_ feed: AtomFeed) -> [RawItem] {
        (feed.entries ?? []).compactMap { entry -> RawItem? in
            guard let title = entry.title?.nonEmpty else { return nil }
            let href = entry.links?.first(where: { $0.attributes?.rel == nil
                                                    || $0.attributes?.rel == "alternate" })?
                .attributes?.href
                ?? entry.links?.first?.attributes?.href
            guard let hrefString = href, let url = URL(string: hrefString) else { return nil }
            let snippet = entry.summary?.value ?? entry.content?.value
            return RawItem(
                title: title,
                url: url,
                publishedAt: entry.updated ?? entry.published,
                snippet: snippet?.nonEmpty,
                transcript: nil,
                sourceKind: .rss,
                author: entry.authors?.first?.name
            )
        }
    }

    private static func normalize(_ feed: JSONFeed) -> [RawItem] {
        (feed.items ?? []).compactMap { item -> RawItem? in
            guard let title = (item.title ?? item.summary)?.nonEmpty,
                  let link = item.url.flatMap(URL.init(string:)) else { return nil }
            return RawItem(
                title: title,
                url: link,
                publishedAt: item.datePublished,
                snippet: item.summary?.nonEmpty,
                transcript: nil,
                sourceKind: .rss,
                author: item.author?.name
            )
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
