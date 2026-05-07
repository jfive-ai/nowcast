import Foundation

/// Identifies which LLM backend the user has selected as active.
/// Persisted as the raw string in `UserDefaults`.
enum LLMProvider: String, CaseIterable, Identifiable {
    case openAI
    case anthropic
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .ollama:    return "Ollama (local)"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:    return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-6"
        case .ollama:    return "llama3.2"
        }
    }

    /// Keychain account holding this provider's secret. `nil` for providers
    /// that don't use one (Ollama runs locally and is unauthenticated).
    var keychainAccount: String? {
        switch self {
        case .openAI:    return KeychainAccount.openAI
        case .anthropic: return KeychainAccount.anthropic
        case .ollama:    return nil
        }
    }
}
