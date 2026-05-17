#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P7-1 citation popover with reliability badge + a small
// "Source reliability" overview list.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = ReliabilitySpec()
        .frame(width: 1100, height: 720, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: cg)
    if let png = bmp.representation(using: .png, properties: [:]) {
        let url = outDir.appendingPathComponent("p7-1-source-reliability.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct ReliabilitySpec: View {
    struct Row { let host: String; let mentions: Int; let up: Int; let down: Int; let hall: Int; let score: Int; let band: String; let color: Color }
    let rows: [Row] = [
        Row(host: "reuters.com",        mentions: 87, up: 22, down: 1,  hall: 0, score: 96, band: "OK",    color: .green),
        Row(host: "coindesk.com",       mentions: 64, up: 12, down: 3,  hall: 0, score: 84, band: "OK",    color: .green),
        Row(host: "blockworks.co",      mentions: 41, up: 6,  down: 2,  hall: 0, score: 73, band: "OK",    color: .green),
        Row(host: "ethfoundation.org",  mentions: 19, up: 2,  down: 1,  hall: 0, score: 62, band: "Mixed", color: .yellow),
        Row(host: "news.ycombinator.com", mentions: 132, up: 4, down: 4, hall: 0, score: 50, band: "Mixed", color: .yellow),
        Row(host: "reddit.com",         mentions: 96, up: 3,  down: 8,  hall: 1, score: 41, band: "Mixed", color: .yellow),
        Row(host: "obscure-blog.net",   mentions: 11, up: 0,  down: 2,  hall: 2, score: 28, band: "Watch", color: .red),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            popover
                .frame(width: 360)
            list
        }
        .padding(24)
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("reuters.com")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(Capsule())
                Text("News").font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal.fill").font(.caption2)
                    Text("OK").font(.caption2.bold())
                }.foregroundStyle(.green)
                Spacer()
                Text("May 16, 2026").font(.caption2).foregroundStyle(.secondary)
            }
            Text("Ethereum's Pectra upgrade activation confirmed for May 22 after Sepolia rehearsal completes cleanly")
                .font(.headline)
            Text("Client teams from Geth, Nethermind, and Besu confirmed the final Sepolia rehearsal completed without consensus issues. Mainnet activation block targets May 22 at approximately 14:00 UTC.")
                .font(.caption).lineLimit(6)
            HStack {
                Label("Jane Reporter", systemImage: "person").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Label("Open", systemImage: "arrow.up.right.square").font(.caption.bold()).foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 10)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source reliability").font(.headline)
            Text("Derived from your thumbs-up / thumbs-down / hallucination feedback on the clusters where each host appeared.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(0..<rows.count, id: \.self) { i in
                row(rows[i])
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ r: Row) -> some View {
        HStack {
            Text(r.host).font(.callout).bold().frame(width: 200, alignment: .leading)
            Text("\(r.mentions) mentions").font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(width: 100, alignment: .leading)
            HStack(spacing: 6) {
                Label("\(r.up)", systemImage: "hand.thumbsup").font(.caption2).foregroundStyle(.green)
                Label("\(r.down)", systemImage: "hand.thumbsdown").font(.caption2).foregroundStyle(.orange)
                Label("\(r.hall)", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.red)
            }
            .frame(width: 130, alignment: .leading)
            Spacer()
            scoreBar(value: r.score, color: r.color)
                .frame(width: 100)
            HStack(spacing: 3) {
                Image(systemName: r.band == "OK" ? "checkmark.seal.fill" : r.band == "Mixed" ? "questionmark.circle" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text(r.band).font(.caption2.bold())
            }.foregroundStyle(r.color)
            Text("\(r.score)").font(.caption.monospacedDigit()).frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func scoreBar(value: Int, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15)).frame(height: 6)
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: geo.size.width * CGFloat(value) / 100, height: 6)
            }
        }
        .frame(height: 8)
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
