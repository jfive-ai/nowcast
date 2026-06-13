import Foundation
import Network

/// Guards outbound fetches against SSRF. The app pulls user- and
/// LLM-supplied URLs (RSS feeds, Nitter mirrors, webhook endpoints); without
/// a guard a malicious feed/webhook could point Nowcast at `localhost`, a
/// private LAN host, or the cloud metadata endpoint (169.254.169.254) and use
/// the app as a confused deputy.
///
/// `validationError(for:)` is a pure function (unit-tested by the headless
/// self-check). `guardedSession` is a shared `URLSession` whose delegate also
/// re-applies the policy on every HTTP redirect, so a public URL can't 302 its
/// way to an internal host.
///
/// Known limitation: this validates the *literal* host/IP. It does not defend
/// against DNS rebinding (a name that resolves to a public IP at check time
/// and a private one at connect time); fully closing that needs custom socket
/// binding. The redirect guard + literal-IP blocking covers the common cases.
enum OutboundURLPolicy {

    /// Returns a human-readable reason the URL is disallowed, or `nil` if it's
    /// safe to fetch.
    static func validationError(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return "Only http and https URLs are allowed."
        }
        guard let rawHost = url.host, !rawHost.isEmpty else {
            return "URL has no host."
        }
        // `URL.host` preserves a trailing FQDN-root dot ("localhost." ,
        // "printer.local."), which resolves identically but slips past naive
        // suffix/equality checks. Normalize before matching.
        var host = rawHost.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        if host == "localhost"
            || host == "localhost.localdomain"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host.hasSuffix(".internal") {
            return "Local or internal hostnames are not allowed."
        }
        if let v4 = IPv4Address(host), isBlocked(ipv4: [UInt8](v4.rawValue)) {
            return "Loopback, private, or link-local addresses are not allowed."
        }
        if let v6 = IPv6Address(host), isBlocked(ipv6: [UInt8](v6.rawValue)) {
            return "Loopback, private, or link-local addresses are not allowed."
        }
        return nil
    }

    static func allows(_ url: URL) -> Bool { validationError(for: url) == nil }

    // MARK: - IP range checks

    static func isBlocked(ipv4 b: [UInt8]) -> Bool {
        guard b.count == 4 else { return true }
        switch b[0] {
        case 0:   return true                       // 0.0.0.0/8 "this network"
        case 10:  return true                       // 10/8 private
        case 127: return true                       // 127/8 loopback
        case 169: return b[1] == 254                // 169.254/16 link-local (incl. metadata)
        case 172: return (16...31).contains(b[1])   // 172.16/12 private
        case 192: return b[1] == 168                // 192.168/16 private
        case 100: return (64...127).contains(b[1])  // 100.64/10 CGNAT
        case 224...255: return true                 // multicast + reserved + broadcast
        default:  return false
        }
    }

    static func isBlocked(ipv6 b: [UInt8]) -> Bool {
        guard b.count == 16 else { return true }
        if b.allSatisfy({ $0 == 0 }) { return true }                       // :: unspecified
        if b[0...14].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true } // ::1 loopback
        if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return true }           // fe80::/10 link-local
        if (b[0] & 0xfe) == 0xfc { return true }                           // fc00::/7 unique-local
        if b[0] == 0xff { return true }                                    // ff00::/8 multicast
        // IPv4-mapped ::ffff:a.b.c.d — re-check the embedded v4.
        if b[0...9].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff {
            return isBlocked(ipv4: Array(b[12...15]))
        }
        return false
    }

    // MARK: - Guarded session

    /// Shared session that blocks redirects to disallowed hosts and caps
    /// request/resource time. Adapters that fetch user-supplied URLs default
    /// to this instead of `URLSession.shared`.
    static let guardedSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: RedirectGuardDelegate.shared, delegateQueue: nil)
    }()
}

/// Re-applies `OutboundURLPolicy` on every HTTP redirect. Returning a nil
/// request to the completion handler stops the redirect from being followed
/// (the task completes with the 3xx response instead of chasing it inward).
final class RedirectGuardDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = RedirectGuardDelegate()

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, OutboundURLPolicy.allows(url) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}
