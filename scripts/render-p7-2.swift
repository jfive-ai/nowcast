#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P7-2 smart-title surface in history + report header.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = SmartTitlesSpec()
        .frame(width: 1100, height: 680, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: cg)
    if let png = bmp.representation(using: .png, properties: [:]) {
        let url = outDir.appendingPathComponent("p7-2-smart-titles.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct SmartTitlesSpec: View {
    struct Row { let title: String; let topic: String; let date: String; let weekly: Bool }
    let history: [Row] = [
        Row(title: "Pectra lands May 22 as restaking TVL crosses 5.6M", topic: "ethereum", date: "May 16", weekly: false),
        Row(title: "EF treasury sells 1,000 ETH; sceptics flag 2024 precedent", topic: "ethereum", date: "May 15", weekly: false),
        Row(title: "EigenLayer + Symbiotic publish joint interop spec", topic: "ethereum", date: "May 14", weekly: false),
        Row(title: "Anthropic releases Claude 4.7 with 1M context", topic: "ai safety", date: "May 13", weekly: false),
        Row(title: "Week of May 16: Pectra, restaking, EF treasury moves", topic: "ETH daily", date: "May 16", weekly: true),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 380)
            Divider()
            reportPane
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("History").font(.headline); Spacer() }
                .padding(12)
            Divider()
            ForEach(0..<history.count, id: \.self) { i in
                let h = history[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if h.weekly {
                            Label("Weekly", systemImage: "calendar.badge.clock")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.18))
                                .foregroundStyle(Color.purple)
                                .clipShape(Capsule())
                        }
                        Text(h.title).font(.callout).bold().lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Text(h.topic).font(.caption2).foregroundStyle(.secondary)
                        Text("·").font(.caption2).foregroundStyle(.secondary)
                        Text(h.date).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(i == 0 ? Color.accentColor.opacity(0.12) : Color.clear)
            }
            Spacer()
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var reportPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pectra lands May 22 as restaking TVL crosses 5.6M")
                .font(.largeTitle).bold()
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor).font(.caption2)
                Text("Smart title").font(.caption2).foregroundStyle(.secondary)
                Text("· raw topic: ethereum").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("May 16, 2026"); Text("·"); Text("Today"); Text("·"); Text("18 items")
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("TL;DR").font(.headline)
            bullet("Pectra activation window confirmed for May 22; client teams green-lit on Sepolia.")
            bullet("Restaking TVL ticked up 4% after Symbiotic-EigenLayer interop announcement.")
            bullet("EF treasury sold 1,000 ETH — labelled as routine operating spend, not a market signal.")
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·").bold()
            Text(s).font(.callout)
        }
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
