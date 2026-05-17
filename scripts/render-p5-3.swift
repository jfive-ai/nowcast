#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P5-3 cluster rows with counterpoint + gap chips inline.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = CounterpointsSpec()
        .frame(width: 980, height: 760, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: cg)
    if let png = bmp.representation(using: .png, properties: [:]) {
        let url = outDir.appendingPathComponent("p5-3-counterpoints.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct CounterpointsSpec: View {
    struct Item {
        let headline: String
        let summary: String
        let counter: String?
        let gap: String?
    }
    let items: [Item] = [
        Item(
            headline: "Pectra activation window confirmed",
            summary: "Client teams completed final Sepolia rehearsals; mainnet activation targeted for May 22. EIP-7702 included.",
            counter: "Multi-client coordination has slipped before — a single-client regression caught during exec-layer dress rehearsal could push activation 1–2 weeks.",
            gap: "Doesn't model L2 readiness — most major rollups still need to confirm their EIP-7702 pathway."
        ),
        Item(
            headline: "Restaking TVL up 4%",
            summary: "Symbiotic and EigenLayer published a joint interop spec. Aggregate restaked ETH crossed 5.6M.",
            counter: "The interop spec doesn't address slashing-coordination risk; concentration in 2 operators means tail risk is rising, not falling.",
            gap: "Brief doesn't surface how much of the 4% is organic vs. pre-existing pledges rotating."
        ),
        Item(
            headline: "EF treasury sold 1,000 ETH",
            summary: "Foundation labelled the sale as routine operating budget covering through Q3.",
            counter: "Reuters [I7] notes that EF treasury sales in 2024 also preceded a local top — the 'routine' framing is consistent with prior tops.",
            gap: nil
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ethereum")
                .font(.largeTitle).bold()
            HStack(spacing: 6) {
                Text("May 16, 2026")
                Text("·")
                Text("Today")
                Text("·")
                Text("18 items")
                Text("·")
                Text("Counterpoints: ON")
                    .foregroundStyle(Color.orange)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()

            Text("Clusters").font(.headline)

            ForEach(0..<items.count, id: \.self) { idx in
                let it = items[idx]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(it.headline).font(.subheadline).bold()
                        Spacer()
                        Image(systemName: "star").foregroundStyle(.secondary)
                        Image(systemName: "hand.thumbsup").foregroundStyle(.secondary)
                        Image(systemName: "hand.thumbsdown").foregroundStyle(.secondary)
                        Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                    }
                    Text(it.summary).font(.caption).foregroundStyle(.secondary)
                    if let c = it.counter {
                        chip(symbol: "exclamationmark.triangle", color: .orange, label: "Counter", text: c)
                    }
                    if let g = it.gap {
                        chip(symbol: "questionmark.circle", color: .blue, label: "Not covered", text: g)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func chip(symbol: String, color: Color, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).bold().foregroundStyle(color)
                Text(text).font(.caption)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.10)))
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
