#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P6-4 follow-up strip on a stub ReportView.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = FollowUpSpec()
        .frame(width: 1100, height: 700, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: cg)
    if let png = bmp.representation(using: .png, properties: [:]) {
        let url = outDir.appendingPathComponent("p6-4-follow-ups.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct FollowUpSpec: View {
    struct Sug { let name: String; let query: String; let sources: String }
    let suggestions: [Sug] = [
        Sug(name: "ETH staking deep-dive", query: "ethereum staking validator economics", sources: "Hacker News · Reddit"),
        Sug(name: "Restaking weekly", query: "eigenlayer symbiotic restaking", sources: "News"),
        Sug(name: "L2 readiness", query: "L2 rollup pectra readiness", sources: "Hacker News · RSS"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ethereum").font(.largeTitle).bold()
            HStack(spacing: 6) {
                Text("May 16, 2026"); Text("·"); Text("Today"); Text("·"); Text("18 items")
            }
            .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                    Text("Follow-ups").font(.caption.bold()).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(0..<suggestions.count, id: \.self) { i in
                        chip(suggestions[i])
                    }
                    Spacer()
                }
            }
            Divider()
            Text("TL;DR").font(.headline)
            Text("· Pectra activation window confirmed for next week; client teams green-lit on Sepolia.").font(.callout)
            Text("· Restaking TVL ticked up 4% after Symbiotic-EigenLayer interop announcement.").font(.callout)
            Text("· EF treasury sold 1,000 ETH — labelled as routine operating spend.").font(.callout)

            Text("Stories").font(.headline).padding(.top, 6)
            Text("Pectra activation window confirmed").font(.subheadline).bold()
            Text("Client teams completed final Sepolia rehearsals; mainnet activation targeted for May 22.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }

    private func chip(_ s: Sug) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.name).font(.caption.bold()).lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "plus.circle").font(.caption2).foregroundStyle(Color.accentColor)
                Text(s.query).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(s.sources).font(.caption2).foregroundStyle(.secondary.opacity(0.8)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.30), lineWidth: 0.5))
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
