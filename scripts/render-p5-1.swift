#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders a representative screenshot of the P5-1 "Chat with Brief" drawer
// alongside a stub of the ReportView body — mirrors what the user sees in
// the running app, without requiring an actual app launch.
//
// Run:  ./scripts/render-p5-1.swift
// Output: $PWD/screenshots/p5-1-chat-with-brief.png

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = ChatWithBriefSpec()
        .frame(width: 1200, height: 760, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: cg)
    if let png = bmp.representation(using: .png, properties: [:]) {
        let url = outDir.appendingPathComponent("p5-1-chat-with-brief.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

// MARK: - Spec

struct ChatWithBriefSpec: View {
    var body: some View {
        HStack(spacing: 0) {
            briefPane
                .frame(width: 760)
            Divider()
            chatPane
        }
    }

    private var briefPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ethereum")
                .font(.largeTitle).bold()
            HStack(spacing: 6) {
                Text("May 16, 2026")
                Text("11:31 AM")
                Text("·")
                Text("Today")
                Text("·")
                Text("18 items")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("3,742 tokens · $0.04 · gpt-4o-mini")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()

            Text("TL;DR").font(.headline)
            bullet("Pectra activation window confirmed for next week; client teams green-lit on Sepolia.")
            bullet("Restaking TVL ticked up 4% after Symbiotic-EigenLayer interop announcement.")
            bullet("EF treasury sold 1,000 ETH — labelled as routine operating spend, not a market signal.")

            Text("Stories").font(.headline).padding(.top, 6)
            story(
                headline: "Pectra activation window confirmed",
                body: "Client teams completed final Sepolia rehearsals; mainnet activation targeted for May 22."
            )
            story(
                headline: "Restaking TVL up 4%",
                body: "Symbiotic and EigenLayer published a joint interop spec. Aggregate restaked ETH crossed 5.6M."
            )
            story(
                headline: "EF treasury sold 1,000 ETH",
                body: "Foundation labelled the sale as routine operating budget covering through Q3."
            )

            Text("Signal").font(.headline).padding(.top, 6)
            Text("Most week-on-week movement is in restaking; staking-rate stability suggests the EF sale is genuinely operational, not a top-tick. Pectra is the next real catalyst.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·").font(.body).bold()
            Text(s).font(.callout)
        }
    }

    private func story(headline: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline).font(.subheadline).bold()
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }

    // MARK: - Chat drawer pane

    private var chatPane: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Chat with this brief", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Spacer()
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                userBubble("Is the EF treasury sale a market signal or routine?")
                assistantBubble(
                    text: "Per the brief, the Foundation labelled it as routine operating spend covering through Q3; no new treasury policy. The Signal section explicitly downplays it as a market signal, citing staking-rate stability.",
                    chips: ["coindesk.com", "ethfoundation.org"]
                )
                userBubble("What's the strongest counter-argument?")
                assistantBubble(
                    text: "The brief does not include a steel-manned counter, but Reuters [I7] notes that EF treasury sales in 2024 also preceded a local top — that's the closest counter-signal in the linked sources.",
                    chips: ["reuters.com"]
                )
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                        .frame(height: 28)
                    Text("Ask a follow-up… (⌘↩ to send)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.horizontal, 8)
                }
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .padding(12)
        }
        .frame(width: 420)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func userBubble(_ s: String) -> some View {
        HStack {
            Spacer(minLength: 24)
            Text(s)
                .padding(10)
                .background(Color.accentColor.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func assistantBubble(text: String, chips: [String]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .padding(10)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 4) {
                    ForEach(chips, id: \.self) { c in
                        Text(c).font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer(minLength: 24)
        }
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in
    renderAll()
    exit(0)
}
_ = task
RunLoop.main.run()
