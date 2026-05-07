import Foundation

/// Approximate USD pricing per 1M tokens for known models. Prices change
/// — these are reasonable as of 2026-Q2 and used only to give the user a
/// rough "this report cost ~$X" signal in the UI. Always rounded down to
/// the lowest meaningful precision so we don't imply false accuracy.
enum ModelPricing {
    struct Entry {
        /// Match if model identifier *starts with* this prefix. Prefixes are
        /// tried longest-first so `gpt-4o-mini` doesn't get caught by `gpt-4o`.
        let prefix: String
        let inputUSDPerMillion: Double
        let outputUSDPerMillion: Double
    }

    static let entries: [Entry] = [
        // OpenAI
        .init(prefix: "gpt-4o-mini",  inputUSDPerMillion: 0.15,  outputUSDPerMillion: 0.60),
        .init(prefix: "gpt-4o",       inputUSDPerMillion: 2.50,  outputUSDPerMillion: 10.00),
        .init(prefix: "gpt-4-turbo",  inputUSDPerMillion: 10.00, outputUSDPerMillion: 30.00),
        .init(prefix: "gpt-3.5",      inputUSDPerMillion: 0.50,  outputUSDPerMillion: 1.50),
        // Anthropic Claude
        .init(prefix: "claude-haiku-4",  inputUSDPerMillion: 1.00,  outputUSDPerMillion: 5.00),
        .init(prefix: "claude-sonnet-4", inputUSDPerMillion: 3.00,  outputUSDPerMillion: 15.00),
        .init(prefix: "claude-opus-4",   inputUSDPerMillion: 15.00, outputUSDPerMillion: 75.00),
        // Local — never costs money
        .init(prefix: "llama",   inputUSDPerMillion: 0, outputUSDPerMillion: 0),
        .init(prefix: "qwen",    inputUSDPerMillion: 0, outputUSDPerMillion: 0),
        .init(prefix: "mistral", inputUSDPerMillion: 0, outputUSDPerMillion: 0),
        .init(prefix: "gemma",   inputUSDPerMillion: 0, outputUSDPerMillion: 0),
        .init(prefix: "phi",     inputUSDPerMillion: 0, outputUSDPerMillion: 0),
    ]

    /// Look up pricing by longest matching prefix. Returns `nil` if the
    /// model isn't recognized.
    static func entry(forModel model: String) -> Entry? {
        let lower = model.lowercased()
        return entries
            .filter { lower.hasPrefix($0.prefix) }
            .max(by: { $0.prefix.count < $1.prefix.count })
    }

    /// Estimated USD cost for a single LLM call, or `nil` if pricing is
    /// unknown for the model.
    static func cost(forModel model: String, usage: LLMUsage) -> Double? {
        guard let entry = entry(forModel: model) else { return nil }
        let input = Double(usage.promptTokens) * entry.inputUSDPerMillion / 1_000_000
        let output = Double(usage.completionTokens) * entry.outputUSDPerMillion / 1_000_000
        return input + output
    }
}
