import Foundation

/// Reddit search via the unauthenticated `.json` endpoint. No API key, but
/// Reddit aggressively rate-limits anonymous traffic — set a descriptive
/// User-Agent and keep request volume modest.
///
/// With no Reddit subscriptions: searches all of Reddit for `query`.
/// With one or more `.reddit` subscriptions: searches inside each subreddit
/// and merges the results. This lets the user say "ETH news, but only from
/// /r/ethereum + /r/ethfinance" by attaching subscriptions to the preset.
struct RedditAdapter: SourceAdapter {
    let kind: SourceKind = .reddit

    private let session: URLSession
    private let userAgent: String

    init(session: URLSession = .shared,
         userAgent: String = "Nowcast/0.1 (macOS; +https://github.com/jfive-ai/nowcast)") {
        self.session = session
        self.userAgent = userAgent
    }

    func fetch(query: String,
               window: TimeWindow,
               subscriptions: [SourceSubscription]) async throws -> [RawItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let subreddits = subscriptions
            .filter { $0.kind == .reddit }
            .map { $0.identifier }
            .filter { !$0.isEmpty }

        if subreddits.isEmpty {
            return try await searchGlobal(query: trimmed, window: window)
        }
        return try await searchSubreddits(subreddits, query: trimmed, window: window)
    }

    // MARK: - Internals

    private func searchGlobal(query: String, window: TimeWindow) async throws -> [RawItem] {
        guard let url = makeURL(path: "/search.json", query: query, window: window) else {
            return []
        }
        return try await fetchListing(url: url, cutoff: window.earliestDate)
    }

    private func searchSubreddits(_ subreddits: [String], query: String, window: TimeWindow) async throws -> [RawItem] {
        let cutoff = window.earliestDate
        return try await withThrowingTaskGroup(of: [RawItem].self) { group in
            for sub in subreddits {
                let cleaned = Self.normalizeSubreddit(sub)
                guard !cleaned.isEmpty,
                      let url = makeURL(
                        path: "/r/\(cleaned)/search.json",
                        query: query,
                        window: window,
                        restrictToSubreddit: true
                      )
                else { continue }
                group.addTask {
                    // A single broken subreddit shouldn't poison the whole run.
                    do { return try await fetchListing(url: url, cutoff: cutoff) } catch { return [] }
                }
            }
            var all: [RawItem] = []
            for try await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    private func makeURL(path: String,
                         query: String,
                         window: TimeWindow,
                         restrictToSubreddit: Bool = false) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "www.reddit.com"
        c.path = path
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: "new"),
            URLQueryItem(name: "t", value: Self.redditTime(for: window)),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        if restrictToSubreddit {
            items.append(URLQueryItem(name: "restrict_sr", value: "on"))
        }
        c.queryItems = items
        return c.url
    }

    private func fetchListing(url: URL, cutoff: Date) async throws -> [RawItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SourceError.requestFailed(kind: .reddit)
        }
        let parsed = try JSONDecoder().decode(RedditListing.self, from: data)

        return parsed.data.children.compactMap { child in
            let post = child.data
            guard let title = post.title,
                  let permalink = post.permalink,
                  let permalinkURL = URL(string: "https://www.reddit.com\(permalink)") else {
                return nil
            }
            let published = Date(timeIntervalSince1970: post.created_utc ?? 0)
            // The `t=` parameter is approximate on Reddit's side — re-filter
            // here to honor the user's chosen window precisely.
            if published < cutoff { return nil }

            return RawItem(
                title: title,
                url: permalinkURL,
                publishedAt: published,
                snippet: post.selftext?.nonEmpty ?? post.subreddit_name_prefixed,
                transcript: nil,
                sourceKind: .reddit,
                author: post.author
            )
        }
    }

    private static func redditTime(for window: TimeWindow) -> String {
        switch window {
        case .lastHour:  return "hour"
        case .today:     return "day"
        case .last7Days: return "week"
        }
    }

    /// Strip a leading "r/" or "/r/" from a subreddit identifier so the user
    /// can paste either form when creating a subscription.
    private static func normalizeSubreddit(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("/") { s.removeFirst() }
        if s.lowercased().hasPrefix("r/") { s.removeFirst(2) }
        return s
    }

    // MARK: - Decoding

    private struct RedditListing: Decodable {
        let data: ListingData
    }
    private struct ListingData: Decodable {
        let children: [Child]
    }
    private struct Child: Decodable {
        let data: Post
    }
    private struct Post: Decodable {
        let title: String?
        let permalink: String?
        let selftext: String?
        let author: String?
        let subreddit_name_prefixed: String?
        let created_utc: Double?
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
