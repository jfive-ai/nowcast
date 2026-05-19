import Foundation

/// One turn in the chat thread attached to a report (P5-1). Roles match
/// the simple two-actor model the LLM clients already expect.
struct ConversationMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let reportID: UUID
    let role: Role
    let text: String
    /// URLs the model claims it cited. Validated client-side against the
    /// linked items; rendered as small chips under the bubble.
    let citations: [String]
    let createdAt: Date

    init(id: UUID = UUID(),
         reportID: UUID,
         role: Role,
         text: String,
         citations: [String] = [],
         createdAt: Date = Date()) {
        self.id = id
        self.reportID = reportID
        self.role = role
        self.text = text
        self.citations = citations
        self.createdAt = createdAt
    }
}
