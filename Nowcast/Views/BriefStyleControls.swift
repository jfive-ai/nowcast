import SwiftUI

struct BriefStyleControls: View {
    @Binding var depth: BriefDepth
    @Binding var tone: BriefTone

    var body: some View {
        Picker("Depth", selection: $depth) {
            ForEach(BriefDepth.allCases) { depth in
                Text(depth.displayName).tag(depth)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Choose how much detail each briefing includes")
        Picker("Tone", selection: $tone) {
            ForEach(BriefTone.allCases) { tone in
                Text(tone.displayName).tag(tone)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Choose the writing style for this preset")
        Text("Applies to manual and scheduled briefings for this preset. No extra AI calls.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
