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
            return "LLM request failed (\(status)): \(body)"
        case .decodingFailed(let msg):
            return "Could not decode LLM response: \(msg)"
        case .emptyResponse:
            return "LLM returned an empty response."
        }
    }
}
