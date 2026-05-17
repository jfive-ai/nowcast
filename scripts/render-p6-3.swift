#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P6-3 side-by-side compare view.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = CompareSpec()
        .frame(width: 1300, height: 800, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: cg)
    if let png = bmp.representation(using: .png, properties: [:]) {
        let url = outDir.appendingPathComponent("p6-3-compare.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct CompareSpec: View {
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            deltaStrip
            Divider()
            HStack(spacing: 0) {
                pane(date: "May 14, 2026 09:00",
                     bullets: [
                        "Pectra activation targeted late May (window not fixed).",
                        "Restaking TVL at 5.4M ETH; slow-and-steady week.",
                        "EF treasury sold 800 ETH — quiet, no commentary.",
                     ],
                     stories: [
                        ("Pectra activation timeline still soft",
                         "Client teams haven't locked the activation block. Likely between May 22 and May 29."),
                        ("Restaking TVL ticks up modestly",
                         "Aggregate restaked ETH at 5.4M, +1.4% on the week. No new entrants of size."),
                        ("EF treasury sold 800 ETH",
                         "Routine operational sale, no formal announcement."),
                     ])
                Divider()
                pane(date: "May 16, 2026 11:32",
                     bullets: [
                        "Pectra activation window confirmed for May 22 (~14:00 UTC).",
                        "Restaking TVL up 4% on Symbiotic-EigenLayer interop announcement.",
                        "EF treasury sold 1,000 ETH; sceptics flag 2024 precedent.",
                     ],
                     stories: [
                        ("Pectra activation window confirmed",
                         "Sepolia rehearsal completed cleanly; mainnet block targets May 22 ~14:00 UTC. EIP-7702 included."),
                        ("Restaking TVL up 4%",
                         "Symbiotic + EigenLayer joint interop spec lifted aggregate restaked ETH to 5.6M; BIS concentration warning."),
                        ("EF treasury sold 1,000 ETH",
                         "Foundation labels as routine; 2024 precedent surfaced as counter-signal."),
                     ])
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Compare").font(.headline)
                Text("ethereum · May 14, 2026  ↔  ethereum · May 16, 2026")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                metric("Items", "14 → 18")
                metric("Cost", "$0.0312 → $0.0408")
            }
        }
        .padding(12)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private var deltaStrip: some View {
        HStack(spacing: 6) {
            chip("New", color: .green, label: "Pectra activation window confirmed")
            chip("Continuing", color: .blue, label: "Restaking TVL")
            chip("Continuing", color: .blue, label: "EF treasury sale")
            chip("Dropped", color: .gray, label: "Pectra activation timeline still soft")
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
    }

    private func chip(_ kind: String, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Text(kind).font(.caption2.bold())
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(color.opacity(0.20))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(label).font(.caption)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.08)))
    }

    private func pane(date: String, bullets: [String], stories: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(date).font(.subheadline.bold()).padding(.bottom, 2)
            Text("TL;DR").font(.headline)
            ForEach(bullets, id: \.self) { b in
                HStack(alignment: .top, spacing: 4) {
                    Text("·").bold()
                    Text(b).font(.callout)
                }
            }
            Text("Stories").font(.headline).padding(.top, 6)
            ForEach(0..<stories.count, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stories[i].0).font(.subheadline).bold()
                    Text(stories[i].1).font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
