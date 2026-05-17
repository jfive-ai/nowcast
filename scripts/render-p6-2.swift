#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P6-2 provenance drawer beside a stub of the brief body.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = ProvenanceSpec()
        .frame(width: 1200, height: 800, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: cg)
    if let png = bmp.representation(using: .png, properties: [:]) {
        let url = outDir.appendingPathComponent("p6-2-provenance.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct ProvenanceSpec: View {
    struct Item { let title: String; let kind: String; let host: String }
    struct Claim { let text: String; let items: [Item]; let unmatched: String? }
    struct Cluster { let headline: String; let claims: [Claim] }

    let clusters: [Cluster] = [
        Cluster(headline: "Pectra activation window confirmed", claims: [
            Claim(text: "Client teams completed final Sepolia rehearsal.", items: [
                Item(title: "Ethereum Pectra upgrade hits final Sepolia rehearsal", kind: "News", host: "reuters.com"),
                Item(title: "Sepolia test passes — Pectra mainnet date locked", kind: "Hacker News", host: "news.ycombinator.com")
            ], unmatched: nil),
            Claim(text: "Mainnet activation targets May 22 around 14:00 UTC.", items: [
                Item(title: "Pectra goes live May 22", kind: "News", host: "coindesk.com")
            ], unmatched: "ethereum.org/blog"),
        ]),
        Cluster(headline: "Restaking TVL up 4%", claims: [
            Claim(text: "Aggregate restaked ETH crossed 5.6M.", items: [
                Item(title: "EigenLayer + Symbiotic joint interop spec released", kind: "News", host: "blockworks.co")
            ], unmatched: nil),
            Claim(text: "BIS flagged concentration risk in 2 operators.", items: [],
                  unmatched: "bis.org/publ/wp_2026.pdf"),
        ]),
    ]

    var body: some View {
        HStack(spacing: 0) {
            briefStub
            Divider()
            drawer
        }
    }

    private var briefStub: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ethereum").font(.largeTitle).bold()
            Text("May 16, 2026 · Today · 18 items").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("TL;DR").font(.headline)
            Text("· Pectra activation window confirmed for next week; client teams green-lit on Sepolia.").font(.callout)
            Text("· Restaking TVL ticked up 4% after Symbiotic-EigenLayer interop announcement.").font(.callout)
            Text("Stories").font(.headline).padding(.top, 6)
            Text("Pectra activation window confirmed").font(.subheadline).bold()
            Text("Client teams completed final Sepolia rehearsals; mainnet activation targeted for May 22.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Restaking TVL up 4%").font(.subheadline).bold().padding(.top, 6)
            Text("Symbiotic and EigenLayer published a joint interop spec.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
        .frame(width: 720)
    }

    private var drawer: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Provenance", systemImage: "checkmark.seal").font(.headline)
                Spacer()
                Text("4 claims · 4 items").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<clusters.count, id: \.self) { ci in
                    clusterCard(clusters[ci])
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(width: 420)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func clusterCard(_ c: Cluster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.headline).font(.subheadline).bold()
            ForEach(0..<c.claims.count, id: \.self) { i in
                let cl = c.claims[i]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "quote.bubble").font(.caption2).foregroundStyle(.secondary)
                        Text(cl.text).font(.caption)
                    }
                    if cl.items.isEmpty {
                        Label("No matched items in source set", systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(.orange)
                    } else {
                        ForEach(0..<cl.items.count, id: \.self) { j in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "doc.text").font(.caption2).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(cl.items[j].title).font(.caption).bold().lineLimit(2)
                                    HStack(spacing: 4) {
                                        Text(cl.items[j].kind).font(.caption2).foregroundStyle(.secondary)
                                        Text("·").font(.caption2).foregroundStyle(.secondary)
                                        Text(cl.items[j].host).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.05)))
                        }
                    }
                    if let u = cl.unmatched {
                        Text("Other cites: \(u)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
