import Foundation

/// Pulls latest uploads from each subscribed YouTube channel and best-effort
/// fetches a transcript for each. No transcript = `RawItem.transcript`
/// stays nil; the title + description still flow through.
///
/// Subscription identifier accepts:
///   - a channel ID like `UCxxxxxxxxxxxxxxxxxxxxxx`
///   - a handle like `@bankless` (or `bankless`)
///   - a channel URL `https://www.youtube.com/@bankless`
struct YouTubeChannelAdapter: SourceAdapter {
    let kind: SourceKind = .youtubeChannel

    private let session: URLSession
    private let apiKey: String
    private let maxVideosPerChannel: Int

    init(apiKey: String,
         session: URLSession = .shared,
         maxVideosPerChannel: Int = 5) {
        self.apiKey = apiKey
        self.session = session
        self.maxVideosPerChannel = maxVideosPerChannel
    }

    func fetch(query: String,
               window: TimeWindow,
               subscriptions: [SourceSubscription]) async throws -> [RawItem] {
        guard !apiKey.isEmpty else { return [] }
        let identifiers = subscriptions
            .filter { $0.kind == .youtubeChannel }
            .map(\.identifier)
            .filter { !$0.isEmpty }
        guard !identifiers.isEmpty else { return [] }

        let cutoff = window.earliestDate

        return try await withThrowingTaskGroup(of: [RawItem].self) { group in
            for raw in identifiers {
                group.addTask {
                    do {
                        return try await fetchChannel(raw: raw, cutoff: cutoff)
                    } catch {
                        return []
                    }
                }
            }
            var all: [RawItem] = []
            for try await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    // MARK: - Per-channel pipeline

    private func fetchChannel(raw: String, cutoff: Date) async throws -> [RawItem] {
        guard let uploadsPlaylist = try await resolveUploadsPlaylist(raw: raw) else {
            return []
        }
        let videos = try await listPlaylist(playlistId: uploadsPlaylist, cutoff: cutoff)
        return await withTaskGroup(of: RawItem.self) { group in
            for video in videos {
                group.addTask {
                    let transcript = try? await TranscriptFetcher.fetch(videoId: video.videoId)
                    return RawItem(
                        title: video.title,
                        url: video.url,
                        publishedAt: video.publishedAt,
                        snippet: video.description,
                        transcript: transcript,
                        sourceKind: .youtubeChannel,
                        author: video.channelTitle
                    )
                }
            }
            var out: [RawItem] = []
            for await item in group { out.append(item) }
            return out
        }
    }

    /// Two-step: identifier → channel object → uploads playlist id (UU…).
    private func resolveUploadsPlaylist(raw: String) async throws -> String? {
        let normalized = Self.normalize(raw)
        var c = URLComponents()
        c.scheme = "https"
        c.host = "www.googleapis.com"
        c.path = "/youtube/v3/channels"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        switch normalized {
        case .id(let id):     items.append(URLQueryItem(name: "id", value: id))
        case .handle(let h):  items.append(URLQueryItem(name: "forHandle", value: h))
        }
        c.queryItems = items
        guard let url = c.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SourceError.requestFailed(kind: .youtubeChannel)
        }
        let parsed = try JSONDecoder.youtube.decode(ChannelsResponse.self, from: data)
        return parsed.items.first?.contentDetails.relatedPlaylists.uploads
    }

    private func listPlaylist(playlistId: String, cutoff: Date) async throws -> [Video] {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "www.googleapis.com"
        c.path = "/youtube/v3/playlistItems"
        c.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "playlistId", value: playlistId),
            URLQueryItem(name: "maxResults", value: String(maxVideosPerChannel)),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = c.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SourceError.requestFailed(kind: .youtubeChannel)
        }
        let parsed = try JSONDecoder.youtube.decode(PlaylistItemsResponse.self, from: data)
        return parsed.items.compactMap { item -> Video? in
            let publishedAt = item.contentDetails.videoPublishedAt ?? item.snippet.publishedAt
            guard publishedAt >= cutoff else { return nil }
            let videoId = item.contentDetails.videoId ?? item.snippet.resourceId?.videoId
            guard let vid = videoId,
                  let url = URL(string: "https://www.youtube.com/watch?v=\(vid)") else { return nil }
            return Video(
                videoId: vid,
                title: item.snippet.title,
                description: item.snippet.description,
                channelTitle: item.snippet.channelTitle ?? item.snippet.videoOwnerChannelTitle ?? "",
                publishedAt: publishedAt,
                url: url
            )
        }
    }

    // MARK: - Normalization

    private enum NormalizedID {
        case id(String)
        case handle(String)
    }

    private static func normalize(_ raw: String) -> NormalizedID {
        var s = raw.trimmingCharacters(in: .whitespaces)
        // Strip a YouTube URL prefix and pull out the relevant segment.
        if let url = URL(string: s), let host = url.host, host.contains("youtube.com") {
            let comps = url.pathComponents.filter { $0 != "/" }
            if let first = comps.first {
                s = first
                if comps.count >= 2 && (first == "channel" || first == "c" || first == "user") {
                    s = comps[1]
                }
            }
        }
        if s.hasPrefix("UC"), s.count >= 20 {
            return .id(s)
        }
        if s.hasPrefix("@") {
            return .handle(s)
        }
        // Bare handle without "@".
        return .handle("@\(s)")
    }

    private struct Video {
        let videoId: String
        let title: String
        let description: String
        let channelTitle: String
        let publishedAt: Date
        let url: URL
    }

    // MARK: - Decoding

    private struct ChannelsResponse: Decodable {
        let items: [Item]
        struct Item: Decodable {
            let contentDetails: ContentDetails
        }
        struct ContentDetails: Decodable {
            let relatedPlaylists: RelatedPlaylists
        }
        struct RelatedPlaylists: Decodable {
            let uploads: String
        }
    }

    private struct PlaylistItemsResponse: Decodable {
        let items: [Item]
        struct Item: Decodable {
            let snippet: Snippet
            let contentDetails: ContentDetails
        }
        struct Snippet: Decodable {
            let title: String
            let description: String
            let channelTitle: String?
            let videoOwnerChannelTitle: String?
            let publishedAt: Date
            let resourceId: ResourceID?
        }
        struct ResourceID: Decodable {
            let videoId: String?
        }
        struct ContentDetails: Decodable {
            let videoId: String?
            let videoPublishedAt: Date?
        }
    }
}
