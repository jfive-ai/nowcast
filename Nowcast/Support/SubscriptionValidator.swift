import Foundation

/// Per-kind validation for a source subscription identifier, so a typo (an
/// empty field, an RSS "URL" that isn't a URL, an X handle pasted as a full
/// link) is caught at add-time with feedback instead of silently producing a
/// subscription that never returns anything. Pure + unit-checked.
enum SubscriptionValidator {
    /// Returns a human-readable reason the identifier is invalid for `kind`,
    /// or `nil` if it's acceptable.
    static func validationError(kind: SourceKind, identifier raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return "Enter an identifier." }

        switch kind {
        case .rss:
            guard let url = URL(string: id),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty else {
                return "Enter a valid http(s) feed URL."
            }
            return nil

        case .xNitter:
            let handle = id.hasPrefix("@") ? String(id.dropFirst()) : id
            guard !handle.isEmpty, handle.allSatisfy(Self.isHandleChar) else {
                return "Enter an X handle like vitalikbuterin (no URL)."
            }
            return nil

        case .reddit:
            let name = id.lowercased().hasPrefix("r/") ? String(id.dropFirst(2)) : id
            guard !name.isEmpty, name.allSatisfy(Self.isHandleChar) else {
                return "Enter a subreddit name like ethereum."
            }
            return nil

        case .youtubeChannel:
            if id.hasPrefix("UC"), id.count >= 20 { return nil }          // channel id
            if id.hasPrefix("@"), id.count >= 2 { return nil }            // @handle
            if let url = URL(string: id), url.host?.contains("youtube.com") == true { return nil }
            if id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }) {
                return nil                                                // bare handle
            }
            return "Enter a channel ID (UC…), @handle, or youtube.com URL."

        default:
            return nil
        }
    }

    private static func isHandleChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}
