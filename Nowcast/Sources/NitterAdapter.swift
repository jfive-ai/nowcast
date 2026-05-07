import Foundation
import FeedKit

/// Pulls X / Twitter activity via Nitter RSS. Each subscription is an X
/// handle (e.g. `vitalikbuterin` or `@vitalikbuterin`). The adapter walks
/// the user's configured mirror list per handle, falling back to the next
/// mirror on 5xx / timeout / non-RSS payload, and demotes a mirror that
/// fails so flaky ones drift to the bottom of the rotation.
///
/// Nitter mirrors are aggressively rate-limited and frequently die; an
/// empty result for a handle is "no recent activity" rather than an error,
/// per the Phase 2.5 risk note.
struct NitterAdapter: SourceAdapter {
    let kind: SourceKind = .xNitter

    private let session: URLSession
    private let mirrorStore: NitterMirrorStore

    init(mirrorStore: NitterMirrorStore, session: URLSession = .shared) {
        self.session = session
        self.mirrorStore = mirrorStore
    }

    func fetch(query: String,
               window: TimeWindow,
               subscriptions: [SourceSubscription]) async throws -> [RawItem] {
        let handles = subscriptions
            .filter { $0.kind == .xNitter }
            .map { Self.normalizeHandle($0.identifier) }
            .filter { !$0.isEmpty }
        guard !handles.isEmpty else { return [] }

        let mirrors = await MainActor.run { mirrorStore.mirrors }
        guard !mirrors.isEmpty else { return [] }

        let cutoff = window.earliestDate

        return await withTaskGroup(of: [RawItem].self) { group in
            for handle in handles {
                group.addTask {
                    await fetchHandle(handle: handle, mirrors: mirrors, cutoff: cutoff)
                }
            }
            var all: [RawItem] = []
            for await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    // MARK: - Internals

    private func fetchHandle(handle: String, mirrors: [String], cutoff: Date) async -> [RawItem] {
        for base in mirrors {
            guard let url = URL(string: "\(base)/\(handle)/rss") else { continue }
            do {
                let items = try await fetchRSS(from: url, cutoff: cutoff)
                if !items.isEmpty {
                    await MainActor.run { mirrorStore.promote(base) }
                }
                return items
            } catch {
                await MainActor.run { mirrorStore.demote(base) }
                continue
            }
        }
        // All mirrors failed — surface as "no activity" per the phase risk note.
        return []
    }

    private func fetchRSS(from url: URL, cutoff: Date) async throws -> [RawItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Nowcast/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SourceError.requestFailed(kind: .xNitter)
        }

        let feed: Feed = try await withCheckedThrowingContinuation { cont in
            FeedParser(data: data).parseAsync { result in
                switch result {
                case .success(let f): cont.resume(returning: f)
                case .failure(let e): cont.resume(throwing: e)
                }
            }
        }
        guard case .rss(let rss) = feed else {
            throw SourceError.requestFailed(kind: .xNitter)
        }

        return (rss.items ?? []).compactMap { entry -> RawItem? in
            guard let title = entry.title?.nonEmpty,
                  let link = entry.link.flatMap(URL.init(string:)) else { return nil }
            // The RSS link points back to the Nitter mirror; rewrite to
            // the canonical x.com URL so dedup and history stay stable
            // even when the mirror rotates.
            let canonical = Self.canonicalize(link) ?? link
            if let pub = entry.pubDate, pub < cutoff { return nil }
            return RawItem(
                title: title,
                url: canonical,
                publishedAt: entry.pubDate,
                snippet: entry.description?.nonEmpty,
                transcript: nil,
                sourceKind: .xNitter,
                author: entry.author ?? entry.dublinCore?.dcCreator
            )
        }
    }

    /// Rewrites a Nitter post URL (e.g. https://nitter.x/handle/status/123)
    /// to its x.com equivalent so seen-index dedup stays stable across
    /// mirror rotations.
    static func canonicalize(_ url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = "https"
        comps.host = "x.com"
        comps.queryItems = nil
        return comps.url
    }

    static func normalizeHandle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("@") { s.removeFirst() }
        return s
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
