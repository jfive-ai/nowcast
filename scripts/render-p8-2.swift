#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P8-2 "big story" anomaly badge — History list + ReportView
// banner highlighting briefs where sources converge.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = BigStorySpec()
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
        let url = outDir.appendingPathComponent("p8-2-big-story-badge.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct BigStorySpec: View {
    struct Row { let title: String; let topic: String; let date: String; let big: Bool; let weekly: Bool }
    let history: [Row] = [
        Row(title: "Anthropic + OpenAI agree to joint eval benchmark", topic: "ai safety", date: "Jun 06", big: true,  weekly: false),
        Row(title: "Pectra activation rescheduled for May 22",         topic: "ethereum",  date: "Jun 05", big: false, weekly: false),
        Row(title: "EF treasury moves 1,000 ETH",                      topic: "ethereum",  date: "Jun 04", big: false, weekly: false),
        Row(title: "Week of Jun 1: AI safety + Pectra wrap-up",        topic: "ETH daily", date: "Jun 01", big: false, weekly: true),
        Row(title: "Mistral ships open-weight 7B coder",               topic: "ai safety", date: "May 30", big: false, weekly: false),
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
            HStack(spacing: 6) {
                Text("Nowcast").font(.headline)
                Text("🔥").font(.caption)
                Spacer()
                Text("3 unread").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            ForEach(0..<history.count, id: \.self) { i in
                let h = history[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if h.big {
                            Text("🔥").font(.caption2)
                        }
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
            Text("Anthropic + OpenAI agree to joint eval benchmark")
                .font(.largeTitle).bold()

            HStack(spacing: 8) {
                Text("🔥")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Big story").font(.callout).bold()
                    Text("Joint Anthropic–OpenAI safety eval benchmark — 6 of 8 sources converge")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.30), lineWidth: 0.5)
                    )
            )

            HStack(spacing: 6) {
                Text("Jun 06, 2026"); Text("·"); Text("Today"); Text("·"); Text("23 items")
            }
            .font(.caption).foregroundStyle(.secondary)

            Divider()

            Text("TL;DR").font(.headline)
            bullet("Anthropic and OpenAI committed to a shared, public safety-eval benchmark by Q4 2026.")
            bullet("Six independent outlets — NYT, WSJ, BBC, Reuters, FT, Bloomberg — covered the joint statement.")
            bullet("Reuters notes the benchmark suite will include both refusal-quality and dual-use harm metrics.")
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
