import Foundation

/// Persisted SMTP configuration for the email digest delivery channel.
/// Non-secret fields live in `UserDefaults`; the password lives in Keychain
/// under `KeychainAccount.smtpPassword` and is fetched on send.
struct SMTPSettings: Codable, Equatable {
    var host: String
    var port: UInt16
    var username: String
    var fromAddress: String
    var fromName: String
    var recipients: [String]

    static let empty = SMTPSettings(
        host: "",
        port: 465,
        username: "",
        fromAddress: "",
        fromName: "Nowcast",
        recipients: []
    )

    var isConfigured: Bool {
        !host.isEmpty && !username.isEmpty && !fromAddress.isEmpty && !recipients.isEmpty
    }
}

@MainActor
final class SMTPSettingsStore {
    static let shared = SMTPSettingsStore()

    private let defaults: UserDefaults
    private static let key = "nowcast.smtp.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SMTPSettings {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(SMTPSettings.self, from: data) else {
            return .empty
        }
        return decoded
    }

    func save(_ settings: SMTPSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
