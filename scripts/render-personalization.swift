// Render the production style controls with representative preset values.
// swiftc -parse-as-library Nowcast/Models/BriefDepth.swift Nowcast/Models/BriefTone.swift \
//   Nowcast/Views/BriefStyleControls.swift scripts/render-personalization.swift -o /tmp/render-personalization
// /tmp/render-personalization screenshots/p7-3-personalization.png
import AppKit
import SwiftUI

@main
struct RenderPersonalization {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let view = VStack(alignment: .leading, spacing: 16) {
            Text("Edit preset").font(.title2.bold())
            Text("Rust async runtimes").font(.headline)
            Divider()
            Text("Briefing style").font(.headline)
            BriefStyleControls(depth: .constant(.deep), tone: .constant(.technical))
        }
        .padding(24)
        .frame(width: 510)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
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
