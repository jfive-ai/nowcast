import Foundation

/// Estimated reading time for a brief's markdown, used by the at-a-glance stat
/// strip (V4). Pure and testable.
enum ReadingTime {
    static let wordsPerMinute = 220

    static func wordCount(_ markdown: String) -> Int {
        markdown.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    static func minutes(for markdown: String) -> Int {
        let words = wordCount(markdown)
        return max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))
    }
}
