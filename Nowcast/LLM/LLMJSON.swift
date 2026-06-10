import Foundation

/// Decodes a JSON value out of free-form LLM output. Models sometimes wrap
/// the requested JSON in ```json fences or pad it with prose despite prompt
/// instructions, so candidates are tried in order: the first fenced block,
/// the outermost `{…}` / `[…]` span, then the raw trimmed text.
enum LLMJSON {
    static func decode<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        let decoder = JSONDecoder()
        for candidate in candidates(in: raw) {
            guard let data = candidate.data(using: .utf8),
                  let value = try? decoder.decode(T.self, from: data)
            else { continue }
            return value
        }
        return nil
    }

    private static func candidates(in raw: String) -> [String] {
        var out: [String] = []
        if let open = raw.range(of: "```") {
            // Tolerate a missing closing fence — take the rest of the text.
            var body: Substring
            if let close = raw.range(of: "```", range: open.upperBound..<raw.endIndex) {
                body = raw[open.upperBound..<close.lowerBound]
            } else {
                body = raw[open.upperBound...]
            }
            if body.lowercased().hasPrefix("json") { body = body.dropFirst(4) }
            out.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let start = raw.firstIndex(of: "{"),
           let end = raw.lastIndex(of: "}"),
           start <= end {
            out.append(String(raw[start...end]))
        }
        if let start = raw.firstIndex(of: "["),
           let end = raw.lastIndex(of: "]"),
           start <= end {
            out.append(String(raw[start...end]))
        }
        out.append(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        return out
    }
}
