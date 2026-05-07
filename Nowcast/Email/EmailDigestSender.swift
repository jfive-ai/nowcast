import Foundation
import AppKit

/// Renders a generated `Report` into a multipart email and ships it via
/// `SMTPClient`. Markdown is converted to HTML through AppKit's
/// `NSAttributedString(markdown:)` initializer so the rendered body in
/// the recipient's inbox approximates what they'd see in-app.
struct EmailDigestSender {
    let settings: SMTPSettings
    let password: String

    func send(report: Report, markdown: String) async throws {
        guard settings.isConfigured else { return }

        let html = Self.renderHTML(markdown: markdown)
        let message = EmailMessage(
            recipients: settings.recipients,
            subject: "Nowcast: \(report.topic) (\(report.window.displayName))",
            htmlBody: html,
            textBody: markdown
        )

        let client = SMTPClient(config: SMTPClient.Config(
            host: settings.host,
            port: settings.port,
            username: settings.username,
            password: password,
            fromAddress: settings.fromAddress,
            fromName: settings.fromName.isEmpty ? nil : settings.fromName
        ))
        try await client.send(message: message)
    }

    /// Convert markdown to a self-contained HTML document.
    static func renderHTML(markdown: String) -> String {
        let attr: NSAttributedString
        do {
            // `.full` lets paragraph breaks survive; the default
            // `.inlineOnlyPreservingWhitespace` collapses headings and lists.
            let opts = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full
            )
            let parsed = try AttributedString(markdown: markdown, options: opts)
            attr = NSAttributedString(parsed)
        } catch {
            // Worst case, ship the markdown verbatim wrapped in <pre>.
            return "<html><body><pre>\(escapeHTML(markdown))</pre></body></html>"
        }

        let range = NSRange(location: 0, length: attr.length)
        do {
            let data = try attr.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
            )
            return String(data: data, encoding: .utf8)
                ?? "<html><body><pre>\(escapeHTML(markdown))</pre></body></html>"
        } catch {
            return "<html><body><pre>\(escapeHTML(markdown))</pre></body></html>"
        }
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
