import Foundation

struct Report: Identifiable, Codable, Hashable {
    let id: UUID
    let presetID: UUID?
    let topic: String
    let window: TimeWindow
    let generatedAt: Date
    /// Path to the markdown file relative to the reports root.
    let markdownPath: String
    let byteSize: Int64
    let sourceCount: Int
}
