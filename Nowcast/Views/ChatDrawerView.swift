import SwiftUI

/// Right-side drawer attached to a `ReportView` that lets the user ask
/// follow-up questions about the brief (P5-1). Holds a `BriefChatSession`
/// for the report's lifetime in the view tree.
struct ChatDrawerView: View {
    @ObservedObject var session: BriefChatSession
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
        }
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Label("Chat with this brief", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)
            Spacer()
            if !session.messages.isEmpty {
                Button(role: .destructive) {
                    session.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("Clear conversation")
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(session.messages) { msg in
                            bubble(msg)
                                .id(msg.id)
                        }
                    }
                    if session.isThinking {
                        thinkingBubble
                    }
                    if let err = session.lastError {
                        errorBanner(err)
                    }
                }
                .padding(12)
            }
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a follow-up… (⌘↩ to send)", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "paperplane.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isThinking)
            .help("Send (⌘↩)")
        }
        .padding(12)
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Examples")
                .font(.caption).bold()
                .foregroundStyle(.secondary)
            ForEach(Self.examples, id: \.self) { ex in
                Button {
                    input = ex
                    inputFocused = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.secondary)
                        Text(ex)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
        }
    }

    private static let examples: [String] = [
        "What's the most important takeaway in one sentence?",
        "Which claim has the weakest sourcing?",
        "Summarize the counter-argument from the cited items.",
        "Has anything new happened since this brief was generated?",
    ]

    @ViewBuilder
    private func bubble(_ msg: ConversationMessage) -> some View {
        let isUser = msg.role == .user
        HStack {
            if isUser { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 4) {
                Text(msg.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(isUser ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.primary)
                if !msg.citations.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(msg.citations.prefix(6), id: \.self) { url in
                            Link(destination: URL(string: url) ?? URL(string: "about:blank")!) {
                                Text(Self.domain(for: url))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !isUser { Spacer(minLength: 24) }
        }
    }

    private var thinkingBubble: some View {
        HStack {
            ProgressView().controlSize(.small)
            Text("Thinking…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .padding(8)
            .background(Color.red.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let toSend = trimmed
        input = ""
        Task { await session.ask(toSend) }
    }

    private static func domain(for urlString: String) -> String {
        URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }
}
