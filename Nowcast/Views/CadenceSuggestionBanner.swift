import SwiftUI

struct CadenceSuggestionBanner: View {
    let suggestion: CadenceSuggestion
    let presetName: String
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(suggestion.direction == .down ? "Try a slower schedule" : "Try a faster schedule",
                  systemImage: "clock.arrow.circlepath")
                .font(.caption.bold())
            Text(suggestion.reason).font(.caption)
            Text("\(suggestion.currentCadence.displayName) → \(suggestion.proposedCadence.displayName)")
                .font(.caption.bold())
            HStack {
                Button("Apply", action: onApply)
                    .accessibilityLabel("Apply \(suggestion.proposedCadence.displayName) to \(presetName)")
                Button("Dismiss", action: onDismiss)
                    .accessibilityLabel("Dismiss cadence suggestion for \(presetName)")
                    .help("Wait for at least three new runs before suggesting again")
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow.opacity(0.5)))
    }
}
