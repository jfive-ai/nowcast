import SwiftUI

/// Horizontal chip strip rendered above a finished brief, surfacing 3
/// AI-suggested follow-up presets (P6-4). Clicking a chip presents
/// `TopicPresetEditor` pre-filled with the suggestion's name / query /
/// sources, so creating the preset is a single confirmation.
struct FollowUpStrip: View {
    let suggestions: [FollowUpSuggester.Suggestion]
    let onSelect: (FollowUpSuggester.Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("Follow-ups")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(suggestions) { sug in
                    Button {
                        onSelect(sug)
                    } label: {
                        chipBody(sug)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private func chipBody(_ sug: FollowUpSuggester.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sug.name)
                .font(.caption.bold())
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Text(sug.query)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !sug.sources.isEmpty {
                Text(sug.sources.map(\.displayName).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.30), lineWidth: 0.5))
    }
}
