import Foundation
import CryptoKit

/// Deterministic URL canonicalization for dedup.
///
/// Two URLs that point at the same story should canonicalize to the same
/// string (and therefore hash to the same value) regardless of: trailing
/// slash, default port, scheme case, host case, `m.`/`www.` prefix, common
/// tracker params (`utm_*`, `gclid`, `fbclid`, `mc_eid`, `mc_cid`, `ref`,
/// `ref_src`), fragment, or whether YouTube link uses the short or long form.
enum URLCanonicalizer {
    private static let trackerPrefixes: Set<String> = ["utm_"]
    private static let trackerExact: Set<String> = [
        "gclid", "fbclid", "mc_eid", "mc_cid", "ref", "ref_src",
        "igshid", "spm", "_hsenc", "_hsmi", "yclid", "msclkid",
    ]

    // FIX (codex review PR #58): YouTube share-only params are stripped
    // regardless of which URL form was used (`youtu.be/...` or
    // `youtube.com/watch?v=...`). Previously only the short form was
    // normalized, so `youtu.be/abc?t=30` and
    // `youtube.com/watch?v=abc&t=30` hashed differently.
    private static let youtubeShareOnly: Set<String> = [
        "si", "feature", "pp", "t", "ab_channel",
    ]

    static func canonicalize(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        // Scheme: lowercase, drop default ports.
        comps.scheme = comps.scheme?.lowercased()

        // Host: lowercase, strip leading "m." or "www.".
        if var host = comps.host?.lowercased() {
            if host.hasPrefix("www.") { host.removeFirst(4) }
            else if host.hasPrefix("m.") { host.removeFirst(2) }
            comps.host = host
        }

        // Default port removal.
        if comps.scheme == "http" && comps.port == 80 { comps.port = nil }
        if comps.scheme == "https" && comps.port == 443 { comps.port = nil }

        // Strip tracker query items, preserve order of the rest.
        if let items = comps.queryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                if trackerExact.contains(name) { return false }
                if trackerPrefixes.contains(where: { name.hasPrefix($0) }) { return false }
                return true
            }
            comps.queryItems = kept.isEmpty ? nil : kept
        }

        // Strip fragment.
        comps.fragment = nil

        // Drop trailing slash on path (but keep "/" root).
        if comps.path.count > 1, comps.path.hasSuffix("/") {
            comps.path.removeLast()
        }

        // YouTube short → long form.
        // FIX (review #12, codex review PR #58): strip share-only params
        // on BOTH youtu.be and youtube.com/watch URLs so identical videos
        // collapse to the same canonical regardless of which link form
        // was shared.
        if comps.host == "youtu.be", comps.path.count > 1 {
            let videoID = String(comps.path.dropFirst())
            comps.host = "youtube.com"
            comps.path = "/watch"
            var qi = (comps.queryItems ?? []).filter { !Self.youtubeShareOnly.contains($0.name.lowercased()) }
            qi.insert(URLQueryItem(name: "v", value: videoID), at: 0)
            comps.queryItems = qi
        } else if comps.host == "youtube.com" || comps.host == "youtube-nocookie.com" {
            if let items = comps.queryItems {
                let kept = items.filter { !Self.youtubeShareOnly.contains($0.name.lowercased()) }
                comps.queryItems = kept.isEmpty ? nil : kept
            }
        }

        return comps.url ?? url
    }

    /// SHA-256 hex of the canonical URL string. Stable across launches.
    static func hash(_ url: URL) -> String {
        let canonical = canonicalize(url).absoluteString
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
