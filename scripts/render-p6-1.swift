#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P6-1 brief view with a citation popover hovering over a chip.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = CitationHoverSpec()
        .frame(width: 1100, height: 740, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: cg)
    if let png = bmp.representation(using: .png, properties: [:]) {
        let url = outDir.appendingPathComponent("p6-1-citation-popover.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct CitationHoverSpec: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            briefBody
            popoverOverlay
                .offset(x: 380, y: 260)
        }
    }

    private var briefBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ethereum")
                .font(.largeTitle).bold()
            HStack(spacing: 6) {
                Text("May 16, 2026")
                Text("·")
                Text("Today")
                Text("·")
                Text("18 items")
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()

            Text("TL;DR").font(.headline)
            line("Pectra activation window confirmed for next week; client teams green-lit on Sepolia.",
                 chips: [("coindesk.com", false), ("reuters.com", true)])
            line("Restaking TVL ticked up 4% after Symbiotic-EigenLayer interop announcement.",
                 chips: [("blockworks.co", false)])
            line("EF treasury sold 1,000 ETH — labelled as routine operating spend.",
                 chips: [("coindesk.com", false), ("ethfoundation.org", false)])

            Text("Stories").font(.headline).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("Pectra activation window confirmed")
                    .font(.subheadline).bold()
                Text("Client teams completed final Sepolia rehearsals; mainnet activation is targeted for May 22.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    chip(host: "coindesk.com", highlighted: false)
                    chip(host: "reuters.com", highlighted: false)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))

            Spacer()
        }
        .padding(24)
    }

    private func line(_ text: String, chips: [(String, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Text("·").bold()
                Text(text).font(.callout)
            }
            HStack(spacing: 4) {
                ForEach(0..<chips.count, id: \.self) { i in
                    chip(host: chips[i].0, highlighted: chips[i].1)
                }
            }
            .padding(.leading, 14)
        }
    }

    private func chip(host: String, highlighted: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "link.circle.fill")
                .font(.caption2).foregroundStyle(.secondary)
            Text(host).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(highlighted ? Color.accentColor.opacity(0.30) : Color.secondary.opacity(0.10))
        .overlay(Capsule().stroke(highlighted ? Color.accentColor : Color.clear, lineWidth: highlighted ? 1.5 : 0))
        .clipShape(Capsule())
    }

    private var popoverOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("reuters.com")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(Capsule())
                Text("News").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("May 16, 2026").font(.caption2).foregroundStyle(.secondary)
            }
            Text("Ethereum's Pectra upgrade activation confirmed for May 22 after Sepolia rehearsal completes cleanly")
                .font(.headline)
            Text("Client teams from Geth, Nethermind, and Besu confirmed the final Sepolia rehearsal completed without consensus issues. Mainnet activation block targets May 22 at approximately 14:00 UTC; EIP-7702 is included.")
                .font(.caption)
                .lineLimit(6)
            HStack {
                Label("Jane Reporter", systemImage: "person")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Label("Open", systemImage: "arrow.up.right.square")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 14)
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
