#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P5-6 history with a weekly-digest badge + a sample
// weekly-digest report body so reviewers can see what a digest looks like.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = WeeklyDigestSpec()
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
        let url = outDir.appendingPathComponent("p5-6-weekly-digest.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct WeeklyDigestSpec: View {
    let history: [(topic: String, date: String, weekly: Bool)] = [
        ("ETH daily — weekly digest", "May 16", true),
        ("ethereum", "May 16", false),
        ("ethereum", "May 15", false),
        ("ethereum", "May 14", false),
        ("AI safety", "May 14", false),
        ("AI safety — weekly digest", "May 13", true),
        ("ethereum", "May 13", false),
        ("ethereum", "May 12", false),
        ("AI safety", "May 12", false),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 320)
            Divider()
            digestBody
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History").font(.headline)
                Spacer()
            }.padding(12)
            Divider()
            ForEach(0..<history.count, id: \.self) { idx in
                let h = history[idx]
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if h.weekly {
                            Label("Weekly", systemImage: "calendar.badge.clock")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.18))
                                .foregroundStyle(Color.purple)
                                .clipShape(Capsule())
                        }
                        Text(h.topic).font(.callout).lineLimit(1)
                    }
                    Text(h.date).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(idx == 0 ? Color.accentColor.opacity(0.12) : Color.clear)
            }
            Spacer()
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var digestBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Weekly digest", systemImage: "calendar.badge.clock")
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.purple.opacity(0.18))
                    .foregroundStyle(Color.purple)
                    .clipShape(Capsule())
                Spacer()
                Text("Week of May 16, 2026 · 7 daily briefs synthesized")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("ETH daily — weekly digest")
                .font(.largeTitle).bold()
            Divider()

            Text("Storylines").font(.headline)
            bullet("Pectra activation moved from \"targeted late May\" → \"confirmed May 22\" over the week (5 days).")
            bullet("Restaking TVL crept up 4% on the Symbiotic-EigenLayer interop spec (4 days).")
            bullet("EF treasury sales surfaced twice (3 days) — both labelled routine; sceptics cited 2024 precedent.")

            Text("What changed this week").font(.headline).padding(.top, 6)
            bullet("Pectra date hardened: late-May → May 22 [May 14 → May 16].")
            bullet("Restaked-ETH cleared 5.6M from 5.4M [May 12 → May 16].")
            bullet("BIS concentration-risk note flipped from \"watching\" → \"warning\" [May 15].")

            Text("To watch").font(.headline).padding(.top, 6)
            bullet("L2 readiness for EIP-7702 — most rollups still un-public on their pathway [Not covered May 16].")
            bullet("EF Q3 treasury cadence: routine framing vs. 2024 top precedent — open [May 15].")
            bullet("Slashing-coordination risk under the interop spec — flagged but un-addressed [May 14].")

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
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
