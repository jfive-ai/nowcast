import Foundation

protocol LLMClient {
    var providerName: String { get }
    /// Default model identifier for this provider (used when no override).
    var defaultModel: String { get }
    func summarize(prompt: String, model: String?) async throws -> LLMResponse
}

/// What an LLM call returned plus what it cost in tokens. `usage` is `nil`
/// for providers that don't report it (e.g. some local backends).
struct LLMResponse {
    let text: String
    let model: String
    let usage: LLMUsage?
}

struct LLMUsage: Equatable {
    let promptTokens: Int
    let completionTokens: Int

    var totalTokens: Int { promptTokens + completionTokens }
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey
    case requestFailed(status: Int, body: String)
    case decodingFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Add one in Settings."
        case .requestFailed(let status, let body):
            return "LLM request failed (\(status)): \(Self.sanitize(body: body, status: status))"
        case .decodingFailed(let msg):
            return "Could not decode LLM response: \(msg)"
        case .emptyResponse:
            return "LLM returned an empty response."
        }
    }

    /// Turn a raw HTTP error body into something fit for the UI.
    /// CDN-served HTML pages (Cloudflare 502 etc.) get replaced with a
    /// status-based message; standard JSON envelopes get unwrapped to
    /// their `error.message`; everything else is truncated.
    private static func sanitize(body: String, status: Int) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return defaultMessage(forStatus: status) }

        // HTML error page (Cloudflare, nginx, etc.) — don't leak it into the alert.
        if trimmed.hasPrefix("<") {
            return defaultMessage(forStatus: status)
        }

        // OpenAI / Anthropic envelope: { "error": { "message": "..." } } or { "error": "..." }
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String, !msg.isEmpty {
                return msg
            }
            if let msg = json["error"] as? String, !msg.isEmpty {
                return msg
            }
        }

        return String(trimmed.prefix(240))
    }

    private static func defaultMessage(forStatus status: Int) -> String {
        switch status {
        case 401: return "Authentication failed. Check the API key in Settings."
        case 403: return "Forbidden — the API key may not have access to this model."
        case 404: return "Endpoint or model not found."
        case 408: return "Request timed out. Try again."
        case 429: return "Rate limited. Wait a moment and try again."
        case 500: return "Provider returned a server error. Try again."
        case 502: return "Provider is temporarily unreachable (Bad Gateway). Try again in a moment."
        case 503: return "Provider is temporarily unavailable. Try again shortly."
        case 504: return "Provider gateway timed out. Try again."
        default:  return "Provider returned status \(status)."
        }
    }
}
