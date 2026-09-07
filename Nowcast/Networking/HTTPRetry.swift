import Foundation

/// Retrying transport for idempotent HTTP requests. Retries transient failures
/// — connection timeouts / drops and HTTP 408/425/429/5xx — with exponential
/// backoff + full jitter, honoring a `Retry-After` header when the server
/// sends one. Returns the final `(data, response)`; the caller still handles
/// any non-2xx status that survives the retries.
///
/// Used by the LLM clients, where a single transient 429/503 would otherwise
/// abort an entire (paid) report run. The classification/backoff helpers are
/// pure and unit-checked by the headless self-check.
enum HTTPRetry {
    static let defaultMaxAttempts = 3
    static let baseDelay: TimeInterval = 0.5
    static let maxDelay: TimeInterval = 20

    /// HTTP statuses worth retrying (server overload / rate limit / gateway).
    static let transientStatuses: Set<Int> = [408, 425, 429, 500, 502, 503, 504]

    static func isTransient(status: Int) -> Bool { transientStatuses.contains(status) }

    static func isTransient(urlError code: URLError.Code) -> Bool {
        switch code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    /// Delay before the next attempt. `attempt` is the just-failed attempt
    /// number (1-based). Uses `Retry-After` when present, otherwise exponential
    /// backoff with full jitter, capped at `maxDelay`.
    static func delay(forAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter >= 0 { return min(retryAfter, maxDelay) }
        let exp = baseDelay * pow(2, Double(max(0, attempt - 1)))
        return Double.random(in: 0...min(exp, maxDelay))
    }

    /// Parse a `Retry-After` header — either delta-seconds or an HTTP-date.
    static func retryAfterSeconds(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let secs = TimeInterval(raw) { return max(0, secs) }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "GMT")
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = fmt.date(from: raw) { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

    static func data(for request: URLRequest,
                     session: URLSession,
                     maxAttempts: Int = defaultMaxAttempts) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   isTransient(status: http.statusCode),
                   attempt < maxAttempts {
                    let wait = delay(forAttempt: attempt, retryAfter: retryAfterSeconds(http))
                    Log.network.info("HTTP \(http.statusCode, privacy: .public) transient; retry \(attempt, privacy: .public)/\(maxAttempts - 1, privacy: .public) in \(wait, privacy: .public)s")
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    continue
                }
                return (data, response)
            } catch let error as URLError where isTransient(urlError: error.code) && attempt < maxAttempts {
                let wait = delay(forAttempt: attempt, retryAfter: nil)
                Log.network.info("URLError \(error.code.rawValue, privacy: .public) transient; retry \(attempt, privacy: .public)/\(maxAttempts - 1, privacy: .public) in \(wait, privacy: .public)s")
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                continue
            }
        }
    }
}
