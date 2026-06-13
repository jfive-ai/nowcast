import Foundation

/// Scrubs secrets out of strings before they're persisted (e.g. a
/// `source_run.error_message` row) or shown in the UI (`AppState.lastError`).
///
/// `URLSession` errors and webhook/transport failures frequently embed the
/// full request URL — which can carry an `?key=…` API key or a secret webhook
/// path token — so any error text that reaches durable storage or the screen
/// is run through here first. Redaction is pattern-based (it does not need the
/// actual secret values), so it also catches keys the app never held.
enum SecretRedactor {
    private static let patterns: [(NSRegularExpression, String)] = {
        let specs: [(String, String)] = [
            // Secret-bearing query parameters: ?key=… &access_token=… token=…
            (#"(?i)([?&](?:key|api[_-]?key|access[_-]?token|refresh[_-]?token|token|password|passwd|secret|auth|signature|sig)=)[^&\s"'<>]+"#, "$1***"),
            // Authorization: Bearer <token>
            (#"(?i)(bearer\s+)[A-Za-z0-9._\-]+"#, "$1***"),
            // Google API keys (e.g. YouTube Data API).
            (#"AIza[0-9A-Za-z\-_]{10,}"#, "AIza***"),
            // OpenAI / Anthropic / Slack / GitHub style prefixed tokens.
            (#"(?i)\b(sk-ant|sk|pk|xoxb|xoxp|ghp|gho|github_pat)[-_][A-Za-z0-9._\-]{8,}"#, "$1-***"),
        ]
        return specs.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
        }
    }()

    static func redact(_ s: String) -> String {
        var out = s
        for (re, template) in patterns {
            let range = NSRange(out.startIndex..., in: out)
            out = re.stringByReplacingMatches(in: out, range: range, withTemplate: template)
        }
        return out
    }
}

extension Error {
    /// `localizedDescription` with any embedded secrets redacted. Use this
    /// wherever an error string is persisted or displayed.
    var redactedDescription: String {
        SecretRedactor.redact(localizedDescription)
    }
}
