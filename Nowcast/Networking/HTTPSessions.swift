import Foundation

/// Shared `URLSession`s with a **resource** timeout (a cap on total transfer
/// time), which `URLRequest.timeoutInterval` alone doesn't give you — that only
/// bounds the gap between packets. A server that dribbles bytes slowly (flaky
/// Nitter mirrors, Google News under load, a never-ending chunked response) can
/// otherwise hold a connection far past the intended window because the
/// per-request timeout resets on each packet.
///
/// Trusted-host adapters and the LLM clients default to `standard`;
/// user-supplied-URL paths (RSS, Nitter, webhooks) use
/// `OutboundURLPolicy.guardedSession`, which adds SSRF redirect blocking on top
/// of the same timeouts.
enum HTTPSessions {
    /// Trusted-host adapters: small JSON / feeds fetched quickly → 60s total.
    static let standard: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// LLM calls: a completion can legitimately take minutes — a cold-start
    /// local Ollama model (the client budgets 180s) or a long cloud completion
    /// under load — so the resource cap is generous. (`timeoutIntervalForResource`
    /// is session-level and would otherwise override the per-request timeout.)
    static let llm: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 180
        cfg.timeoutIntervalForResource = 300
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()
}
