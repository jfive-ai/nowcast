import Foundation

/// Posts a finished report to a user-supplied webhook URL (P5-4). Three
/// payload formats are supported (Slack, Discord, generic JSON); the
/// caller picks one — or `WebhookFormat.detect(from:)` infers it from
/// the URL host.
///
/// Failures never block the surrounding pipeline — they're returned as a
/// `DeliveryOutcome` for the caller to log.
struct WebhookDeliverer {
    /// What happened when we POSTed. `status == nil` means transport-level
    /// failure (no HTTP response at all).
    struct Outcome: Equatable {
        let status: Int?
        let errorMessage: String?

        var isSuccess: Bool {
            guard let status else { return false }
            return (200..<300).contains(status)
        }
    }

    static let timeout: TimeInterval = 10

    /// Sends a real-report payload using URLSession.
    static func deliver(
        report: Report,
        markdown: String,
        clusters: [BriefingResult.Cluster],
        config: WebhookConfig,
        session: URLSession = .shared
    ) async -> Outcome {
        guard let url = URL(string: config.url) else {
            return Outcome(status: nil, errorMessage: "Invalid webhook URL.")
        }
        let body = renderPayload(report: report, markdown: markdown, clusters: clusters, format: config.format)
        return await post(url: url, body: body, session: session)
    }

    /// Sends a tiny "hello from Nowcast" payload so the user can verify the
    /// URL works before saving the preset.
    static func sendTest(config: WebhookConfig, session: URLSession = .shared) async -> Outcome {
        guard let url = URL(string: config.url) else {
            return Outcome(status: nil, errorMessage: "Invalid webhook URL.")
        }
        let body: Data
        switch config.format {
        case .slack:
            body = jsonData(["text": "Nowcast webhook test — looks good. 👋"])
        case .discord:
            body = jsonData(["content": "Nowcast webhook test — looks good."])
        case .generic:
            body = jsonData([
                "title": "Nowcast test",
                "tldr": ["Webhook reachable."],
                "body_md": "Nowcast webhook test.",
            ])
        }
        return await post(url: url, body: body, session: session)
    }

    // MARK: - Payload rendering

    static func renderPayload(report: Report,
                              markdown: String,
                              clusters: [BriefingResult.Cluster],
                              format: WebhookFormat) -> Data {
        let title = "Nowcast: \(report.topic)"
        let subtitle = "\(report.sourceCount) items · \(report.window.displayName)"
        let tldr = Self.tldrLines(from: markdown)
        let headlines = clusters.prefix(5).map(\.headline)

        switch format {
        case .slack:
            var blocks: [[String: Any]] = [
                ["type": "header",
                 "text": ["type": "plain_text", "text": title]],
                ["type": "context",
                 "elements": [["type": "mrkdwn", "text": subtitle]]],
            ]
            if !tldr.isEmpty {
                let body = tldr.prefix(5).map { "• \($0)" }.joined(separator: "\n")
                blocks.append([
                    "type": "section",
                    "text": ["type": "mrkdwn", "text": body],
                ])
            }
            if !headlines.isEmpty {
                let body = "*Stories*\n" + headlines.map { "• \($0)" }.joined(separator: "\n")
                blocks.append([
                    "type": "section",
                    "text": ["type": "mrkdwn", "text": body],
                ])
            }
            return jsonData([
                "text": title,
                "blocks": blocks,
            ])
        case .discord:
            var embed: [String: Any] = [
                "title": title,
                "description": tldr.prefix(4).map { "• \($0)" }.joined(separator: "\n"),
            ]
            if !headlines.isEmpty {
                embed["fields"] = headlines.prefix(5).map { h -> [String: Any] in
                    ["name": h, "value": "—", "inline": false]
                }
            }
            return jsonData([
                "content": subtitle,
                "embeds": [embed],
            ])
        case .generic:
            return jsonData([
                "title": title,
                "subtitle": subtitle,
                "tldr": Array(tldr.prefix(5)),
                "headlines": Array(headlines),
                "body_md": markdown,
                "report_id": report.id.uuidString,
                "topic": report.topic,
                "generated_at": ISO8601DateFormatter().string(from: report.generatedAt),
            ])
        }
    }

    // MARK: - Transport

    private static func post(url: URL, body: Data, session: URLSession) async -> Outcome {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Nowcast/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            return Outcome(status: status, errorMessage: nil)
        } catch {
            return Outcome(status: nil, errorMessage: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    static func tldrLines(from markdown: String) -> [String] {
        var out: [String] = []
        var inTLDR = false
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("## tl;dr") || trimmed.lowercased().hasPrefix("## tldr") {
                inTLDR = true; continue
            }
            if inTLDR {
                if trimmed.hasPrefix("## ") { break }
                if trimmed.hasPrefix("- ") {
                    out.append(String(trimmed.dropFirst(2)))
                }
            }
        }
        return out
    }

    private static func jsonData(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [])) ?? Data("{}".utf8)
    }
}
