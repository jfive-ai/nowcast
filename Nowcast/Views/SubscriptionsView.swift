import SwiftUI

/// Settings tab listing per-source subscriptions (subreddits, RSS feeds,
/// YouTube channels, etc.) the user wants pulled in addition to (or instead
/// of) generic search. Initially supports Reddit; other kinds come online
/// as their adapters land in Phase 2.
struct SubscriptionsView: View {
    @EnvironmentObject private var state: AppState

    @State private var draftKind: SourceKind = .reddit
    @State private var draftIdentifier: String = ""
    @State private var draftLabel: String = ""
    @State private var suggestTopic: String = ""
    @State private var suggestions: [SourceSubscription] = []

    var body: some View {
        Form {
            Section("Suggest sources") {
                TextField("Topic (e.g. rust async runtime)", text: $suggestTopic)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSuggest() }
                HStack {
                    Spacer()
                    Button {
                        runSuggest()
                    } label: {
                        if state.isSuggesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Suggest")
                        }
                    }
                    .disabled(suggestTopic.trimmingCharacters(in: .whitespaces).isEmpty
                              || state.isSuggesting)
                }
                if !suggestions.isEmpty {
                    ForEach(suggestions) { s in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.label.isEmpty ? s.identifier : s.label)
                                Text("\(s.kind.displayName) · \(s.identifier)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") {
                                state.saveSubscription(s)
                                suggestions.removeAll(where: { $0.id == s.id })
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Add subscription") {
                Picker("Source", selection: $draftKind) {
                    ForEach(Self.subscribableKinds) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                TextField(identifierHint, text: $draftIdentifier)
                    .textFieldStyle(.roundedBorder)
                TextField("Label (optional)", text: $draftLabel)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Add") { add() }
                        .disabled(!isAddValid)
                }
                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Subscriptions") {
                if state.subscriptions.isEmpty {
                    Text("No subscriptions yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.subscriptions) { sub in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.label.isEmpty ? sub.identifier : sub.label)
                                Text("\(sub.kind.displayName) · \(sub.identifier)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                state.deleteSubscription(sub)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var isAddValid: Bool {
        !draftIdentifier.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var identifierHint: String {
        switch draftKind {
        case .reddit:        return "Subreddit (e.g. ethereum)"
        case .rss:           return "Feed URL"
        case .youtubeChannel:return "Channel ID, @handle, or channel URL"
        case .xNitter:       return "X handle (e.g. vitalikbuterin)"
        default:             return "Identifier"
        }
    }

    private var helpText: String {
        switch draftKind {
        case .reddit:
            return "When a Reddit-enabled preset has at least one subreddit subscription, search is restricted to those subreddits."
        case .rss:
            return "RSS subscriptions are fetched on every run; no global search."
        case .youtubeChannel:
            return "Pulls the latest uploads from each subscribed channel and best-effort fetches transcripts when available."
        case .xNitter:
            return "X (Twitter) activity is pulled via Nitter mirrors. Configure mirrors in the Nitter mirrors tab. An empty result means \"no recent activity\" rather than failure."
        default:
            return ""
        }
    }

    private func add() {
        let id = draftIdentifier.trimmingCharacters(in: .whitespaces)
        let label = draftLabel.trimmingCharacters(in: .whitespaces)
        let sub = SourceSubscription(
            kind: draftKind,
            identifier: id,
            label: label.isEmpty ? id : label
        )
        state.saveSubscription(sub)
        draftIdentifier = ""
        draftLabel = ""
    }

    private func runSuggest() {
        let topic = suggestTopic.trimmingCharacters(in: .whitespaces)
        guard !topic.isEmpty, !state.isSuggesting else { return }
        Task {
            suggestions = await state.suggestSubscriptions(topic: topic)
        }
    }

    /// Source kinds that support per-instance subscriptions. (Hacker News
    /// is global-only; web/news searches are global-only.)
    private static let subscribableKinds: [SourceKind] = [
        .reddit,
        .rss,
        .youtubeChannel,
        .xNitter,
    ]
}
