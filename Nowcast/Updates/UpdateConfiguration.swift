import Foundation

/// An unconfigured contributor build never starts network update checks.
struct UpdateConfiguration {
    let feedURL: URL
    let publicKey: String

    init?(feedURL: String?, publicKey: String?) {
        guard let feedURL, let publicKey,
              let url = URL(string: feedURL),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              let key = Data(base64Encoded: publicKey), key.count == 32 else { return nil }
        self.feedURL = url
        self.publicKey = publicKey
    }

    static func read(from bundle: Bundle = .main) -> UpdateConfiguration? {
        UpdateConfiguration(feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
    }
}
