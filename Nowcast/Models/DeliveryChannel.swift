import Foundation

/// How a finished report is surfaced to the user. Backwards-compatible with
/// the pre-P5-4 String-only encoding: existing presets serialized as
/// `"inApp"` / `"email"` / etc still decode correctly.
enum DeliveryChannel: Codable, Hashable, Identifiable {
    case inApp
    case notification
    case menuBar
    case email
    case webhook(WebhookConfig)

    var id: String {
        switch self {
        case .inApp:        return "inApp"
        case .notification: return "notification"
        case .menuBar:      return "menuBar"
        case .email:        return "email"
        case .webhook:      return "webhook"
        }
    }

    var displayName: String {
        switch self {
        case .inApp:        return "In-app only"
        case .notification: return "macOS notification"
        case .menuBar:      return "Menu bar badge"
        case .email:        return "Email digest"
        case .webhook:      return "Webhook"
        }
    }

    /// All plain (non-webhook) channels, for UI lists that show every option.
    static let plainCases: [DeliveryChannel] = [.inApp, .notification, .menuBar, .email]

    var isWebhook: Bool {
        if case .webhook = self { return true } else { return false }
    }

    var webhookConfig: WebhookConfig? {
        if case .webhook(let c) = self { return c } else { return nil }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind, url, format
    }

    init(from decoder: Decoder) throws {
        // Backwards-compat: old encoding was a bare string for the case name.
        if let container = try? decoder.singleValueContainer(),
           let raw = try? container.decode(String.self) {
            switch raw {
            case "inApp":        self = .inApp; return
            case "notification": self = .notification; return
            case "menuBar":      self = .menuBar; return
            case "email":        self = .email; return
            case "webhook":      // shouldn't happen for v0 data but tolerate it
                self = .webhook(WebhookConfig.empty); return
            default:
                self = .inApp; return
            }
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "inApp":        self = .inApp
        case "notification": self = .notification
        case "menuBar":      self = .menuBar
        case "email":        self = .email
        case "webhook":
            let url = try c.decode(String.self, forKey: .url)
            let fmt = (try? c.decode(String.self, forKey: .format)).flatMap(WebhookFormat.init(rawValue:)) ?? .generic
            self = .webhook(WebhookConfig(url: url, format: fmt))
        default:
            self = .inApp
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .webhook(let cfg):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("webhook", forKey: .kind)
            try c.encode(cfg.url, forKey: .url)
            try c.encode(cfg.format.rawValue, forKey: .format)
        default:
            // Preserve the old single-string encoding for the plain cases so
            // pre-P5-4 readers (if any) keep working.
            var c = encoder.singleValueContainer()
            try c.encode(id)
        }
    }
}

struct WebhookConfig: Hashable, Codable {
    var url: String
    var format: WebhookFormat

    static let empty = WebhookConfig(url: "", format: .generic)
}

enum WebhookFormat: String, Codable, CaseIterable, Identifiable {
    case slack
    case discord
    case generic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slack:   return "Slack"
        case .discord: return "Discord"
        case .generic: return "Generic JSON"
        }
    }

    /// Auto-detect format from the URL host. Falls back to `.generic`.
    static func detect(from urlString: String) -> WebhookFormat {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return .generic }
        if host.contains("slack.com") { return .slack }
        if host.contains("discord.com") || host.contains("discordapp.com") { return .discord }
        return .generic
    }
}
