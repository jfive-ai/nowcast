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

    init(mirrorStore: NitterMirrorStore, session: URLSession = OutboundURLPolicy.guardedSession) {
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

        // prod-35: each handle's fetch reports its outcome instead of mutating
        // the shared mirror list inline. With handles fetched concurrently, the
        // old inline promote/demote calls interleaved non-deterministically and
        // hammered the @MainActor store from every task. We collect outcomes,
        // then apply the rotation ONCE after the join, in stable handle order.
        let outcomes = await withTaskGroup(of: (Int, HandleOutcome).self) { group in
            for (index, handle) in handles.enumerated() {
                group.addTask {
                    (index, await fetchHandle(handle: handle, mirrors: mirrors, cutoff: cutoff))
                }
            }
            var collected: [(Int, HandleOutcome)] = []
            for await pair in group { collected.append(pair) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let demotes = outcomes.flatMap(\.failedMirrors)
        let promotes = outcomes.compactMap(\.succeededMirror)
        await MainActor.run {
            // Demote failures first, then promote successes, so a mirror that
            // worked for at least one handle ends up at the front.
            for mirror in demotes { mirrorStore.demote(mirror) }
            for mirror in promotes { mirrorStore.promote(mirror) }
        }
        return outcomes.flatMap(\.items)
    }

    // MARK: - Internals

    private struct HandleOutcome {
        let items: [RawItem]
        /// The mirror that returned items (to promote), or nil.
        let succeededMirror: String?
        /// Mirrors that threw before a success (to demote), in order tried.
        let failedMirrors: [String]
    }

    private func fetchHandle(handle: String, mirrors: [String], cutoff: Date) async -> HandleOutcome {
        var failed: [String] = []
        for base in mirrors {
            guard let url = URL(string: "\(base)/\(handle)/rss"),
                  OutboundURLPolicy.allows(url) else { continue }
            do {
                let items = try await fetchRSS(from: url, cutoff: cutoff)
                if !items.isEmpty {
                    return HandleOutcome(items: items, succeededMirror: base, failedMirrors: failed)
                }
                // prod-21: a 200-but-EMPTY mirror is "up but returned nothing"
                // — often a broken/stale mirror, not genuinely no activity. Try
                // the next mirror before giving up; only after every mirror is
                // exhausted do we report "no activity".
                continue
            } catch {
                failed.append(base)
                continue
            }
        }
        // Every mirror failed or returned empty — surface as "no activity" per
        // the Phase 2.5 risk note (an empty handle is not a report failure).
        if !failed.isEmpty {
            Log.network.notice("Nitter: no items for handle; \(failed.count, privacy: .public) mirror(s) errored")
        }
        return HandleOutcome(items: [], succeededMirror: nil, failedMirrors: failed)
    }

    private func fetchRSS(from url: URL, cutoff: Date) async throws -> [RawItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Nowcast/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SourceError.requestFailed(kind: .xNitter)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SourceError.from(status: http.statusCode, response: http, kind: .xNitter)
        }

        // FeedKit 10 replaced the closure-based `FeedParser` with synchronous
        // throwing initializers on the universal `Feed` type.
        let feed = try Feed(data: data)
        guard case .rss(let rss) = feed else {
            throw SourceError.requestFailed(kind: .xNitter)
        }

        // FeedKit 10 nests items under the <channel> element.
        return (rss.channel?.items ?? []).compactMap { entry -> RawItem? in
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
                author: entry.author ?? entry.dublinCore?.creator
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
