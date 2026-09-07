// Capture production banners using real advisor output and native SwiftUI controls.
// swiftc -parse-as-library Nowcast/Models/{Cadence,CadenceSuggestion,SourceRun,SourceKind}.swift \
//   Nowcast/Pipeline/CadenceAdvisor.swift Nowcast/Views/CadenceSuggestionBanner.swift \
//   scripts/render-cadence.swift -o /tmp/render-cadence
// /tmp/render-cadence screenshots/p7-4-adaptive-cadence.png
import AppKit
import SwiftUI

@main
struct RenderCadence {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        func suggestion(fresh: Int) -> CadenceSuggestion? {
            let rows = (0..<5).map { index in
                let date = Date(timeIntervalSince1970: Double(index) * 3_600)
                return SourceRun(id: UUID(), reportID: UUID(), sourceKind: .hackerNews,
                                 startedAt: date, finishedAt: date.addingTimeInterval(1),
                                 itemsReturned: 10, itemsFresh: fresh, errorMessage: nil)
            }
            return CadenceAdvisor.suggest(recentRuns: rows, currentCadence: .dailyAt(hour: 9, minute: 0))
        }
        let view = VStack(alignment: .leading, spacing: 16) {
            Text("Presets").font(.title2.bold())
            Text("Rust async runtimes").font(.headline)
            if let slower = suggestion(fresh: 0) {
                CadenceSuggestionBanner(suggestion: slower, presetName: "Rust async runtimes", onApply: {}, onDismiss: {})
            }
            Divider()
            Text("AI policy updates").font(.headline)
            if let faster = suggestion(fresh: 9) {
                CadenceSuggestionBanner(suggestion: faster, presetName: "AI policy updates", onApply: {}, onDismiss: {})
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
