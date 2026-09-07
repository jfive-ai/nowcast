import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing per-provider API keys.
/// Each key is stored under (service: bundleID, account: providerName).
struct KeychainStore {
    static let shared = KeychainStore()

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.jfive-ai.nowcast") {
        self.service = service
    }

    // MARK: - Public

    func setSecret(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        try delete(account: account)
        let attrs: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String:   data,
            // ThisDeviceOnly: API keys / the SMTP password are never written to
            // an encrypted backup and never migrate to another device. They're
            // trivially re-entered, so not syncing credentials is the safer
            // default. (Existing items keep their old accessibility until the
            // user next saves the key.)
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func getSecret(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let s): return "Keychain error \(s)"
        }
    }
}

/// Account names live alongside the LLM clients that own them.
enum KeychainAccount {
    static let openAI = "openai.api_key"
    static let anthropic = "anthropic.api_key"
    static let youtube = "youtube.api_key"
    static let braveSearch = "brave.api_key"
    static let smtpPassword = "smtp.password"
}
