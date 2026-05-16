import Foundation

/// Builds the optional `# Avoid` block that gets injected into the briefing
/// prompt when the user has recently dismissed or thumbs-down'd clusters on
/// any topic. Mild signal: the model is asked to deprioritize, not exclude,
/// these themes — false positives shouldn't blow away real news.
enum PreferenceHint {
    static func build(from headlines: [String]) -> String? {
        let trimmed = headlines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return nil }
        let bullets = trimmed.prefix(10).map { "- \($0)" }.joined(separator: "\n")
        return """
        # Avoid (low priority — user previously dismissed)
        Treat the following themes/headlines as low priority unless they are central to the topic. Do not exclude entirely, but prefer other angles when possible:
        \(bullets)
        """
    }
}
