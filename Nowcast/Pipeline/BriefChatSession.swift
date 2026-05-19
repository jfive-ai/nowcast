import Foundation

/// One chat thread anchored to a specific report. Loads the report's
/// markdown + clusters + items once, then concatenates prior turns into
/// each `ask` so the LLMClient single-prompt interface stays unchanged.
///
/// Each successful round-trip persists both turns to `conversation_message`
/// via the supplied `StorageManager`, so reopening the report restores the
/// thread.
@MainActor
final class BriefChatSession: ObservableObject {
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var isThinking: Bool = false
    @Published var lastError: String?

    let report: Report
    private let storage: StorageManager
    private let llm: LLMClient
    private let model: String?

    /// Cached at construction so the system prompt is stable across turns.
    private let briefMarkdown: String
    private let clusters: [BriefingResult.Cluster]
    private let items: [PersistedItem]

    init(report: Report,
         storage: StorageManager,
         llm: LLMClient,
         model: String? = nil) {
        self.report = report
        self.storage = storage
        self.llm = llm
        self.model = model
        self.briefMarkdown = (try? storage.loadMarkdown(for: report)) ?? ""
        self.clusters = (try? storage.clusters(for: report.id)) ?? []
        self.items = (try? storage.itemsForReport(report.id)) ?? []
        self.messages = (try? storage.conversationMessages(forReport: report.id)) ?? []
    }

    /// Sends `question` to the model. On success appends both the user and
    /// assistant turns to `messages` and persists them. On failure leaves
    /// the previous state intact (the user can retry).
    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }

        isThinking = true
        lastError = nil
        defer { isThinking = false }

        let userMessage = ConversationMessage(
            reportID: report.id,
            role: .user,
            text: trimmed
        )

        let prompt = buildPrompt(includingUserMessage: userMessage)

        do {
            let response = try await llm.summarize(prompt: prompt, model: model)
            let assistantText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !assistantText.isEmpty else { throw LLMError.emptyResponse }

            let citations = Self.extractCitations(from: assistantText, knownURLs: items.map(\.canonicalURL.absoluteString))
            let assistantMessage = ConversationMessage(
                reportID: report.id,
                role: .assistant,
                text: assistantText,
                citations: citations
            )

            try storage.insertConversationMessage(userMessage)
            try storage.insertConversationMessage(assistantMessage)

            messages.append(userMessage)
            messages.append(assistantMessage)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clear() {
        try? storage.deleteConversation(forReport: report.id)
        messages.removeAll()
    }

    // MARK: - Prompt assembly

    private func buildPrompt(includingUserMessage user: ConversationMessage) -> String {
        let history = messages.map { msg -> String in
            let label = msg.role == .user ? "User" : "Assistant"
            return "\(label): \(msg.text)"
        }.joined(separator: "\n\n")

        let clusterSummaries = clusters.enumerated().map { idx, c in
            let cites = c.citations.isEmpty ? "" : "\n  sources: \(c.citations.joined(separator: ", "))"
            return "\(idx + 1). \(c.headline)\n  \(c.summary)\(cites)"
        }.joined(separator: "\n")

        let itemSnippets = items.prefix(20).enumerated().map { idx, it in
            let snippet = (it.snippet ?? "").prefix(300)
            return "[I\(idx + 1)] \(it.title) — \(it.canonicalURL.absoluteString)\n  \(snippet)"
        }.joined(separator: "\n\n")

        return """
        You are a research assistant answering a follow-up question about a briefing the user has already read.

        Strict rules:
        - Use ONLY information from the briefing below and the linked source items.
        - When you make a claim, quote a domain or item id (e.g. "[I3]" or "(reuters.com)") that supports it.
        - If the briefing does not cover the question, say so plainly. Do not invent facts.
        - Be concise. ≤ 200 words unless the question demands more.
        - Answer in markdown.

        # The briefing
        Topic: \(report.topic)
        Window: \(report.window.displayName)

        ## Briefing body
        \(briefMarkdown)

        ## Clusters
        \(clusterSummaries.isEmpty ? "(no structured clusters)" : clusterSummaries)

        ## Source items
        \(itemSnippets.isEmpty ? "(no linked items)" : itemSnippets)

        # Conversation so far
        \(history.isEmpty ? "(no prior turns)" : history)

        # New question
        User: \(user.text)

        Assistant:
        """
    }

    /// Returns the subset of `knownURLs` that the response text actually
    /// references. Cheap substring match — good enough for chip display.
    static func extractCitations(from text: String, knownURLs: [String]) -> [String] {
        knownURLs.filter { text.contains($0) }
    }
}
