#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P5-5 ProgressTimelineView overlaid on a stub of the
// main window so the user can see what they'll see while a brief runs.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = StreamingProgressSpec()
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
        let url = outDir.appendingPathComponent("p5-5-streaming-progress.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct StreamingProgressSpec: View {
    let stages: [(name: String, symbol: String, time: String, state: StageState)] = [
        ("Starting ethereum",        "play.circle",                "11:32:01", .done),
        ("Rewriting query",          "text.magnifyingglass",       "11:32:02", .done),
        ("Fetching Hacker News",     "arrow.down.circle",          "11:32:02", .done),
        ("Fetching Reddit",          "arrow.down.circle",          "11:32:02", .done),
        ("Fetched 18 from HN",       "tray.and.arrow.down.fill",   "11:32:05", .done),
        ("Fetched 9 from Reddit",    "tray.and.arrow.down.fill",   "11:32:06", .done),
        ("Deduplicating",            "scissors",                    "11:32:07", .done),
        ("Calling LLM",              "brain.head.profile",         "11:32:07", .done),
        ("LLM responded (3,742 tokens)", "checkmark.bubble",       "11:32:11", .done),
        ("Validating citations",     "shield.checkered",           "11:32:11", .done),
        ("Extracting entities",      "person.crop.circle.dashed",  "11:32:12", .active),
        ("Writing report",           "doc.text",                   "—",         .pending),
    ]
    enum StageState { case done, active, pending }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            mainStub
            overlay
                .padding(16)
        }
    }

    private var mainStub: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Library").font(.headline)
                Text("ETH daily · HN+Reddit").font(.callout)
                Text("AI safety weekly").font(.callout).foregroundStyle(.secondary)
                Divider().padding(.vertical, 8)
                Text("History").font(.headline)
                ForEach(0..<6, id: \.self) { _ in
                    HStack { Text("ethereum"); Spacer(); Text("May 15").foregroundStyle(.secondary) }
                        .font(.callout)
                }
                Spacer()
            }
            .padding(16)
            .frame(width: 280)
            .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            VStack(alignment: .leading) {
                Text("ethereum").font(.largeTitle).bold().padding(.top, 20).padding(.horizontal, 24)
                Text("Working on a fresh brief — see the progress overlay →")
                    .foregroundStyle(.secondary).padding(.horizontal, 24)
                Spacer()
            }
        }
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Generating brief").font(.subheadline).bold()
                    Text("ethereum").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("11.3s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<stages.count, id: \.self) { idx in
                    row(idx)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 12)

            HStack {
                Text("Extracting entities").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(stages.count) stages").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 16)
    }

    @ViewBuilder
    private func row(_ idx: Int) -> some View {
        let s = stages[idx]
        let isLast = idx == stages.count - 1
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Image(systemName: s.symbol)
                    .font(.caption)
                    .foregroundStyle(color(for: s.state))
                    .symbolVariant(s.state == .active ? .fill : .none)
                if !isLast {
                    Rectangle().fill(Color.secondary.opacity(0.30))
                        .frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.callout)
                    .foregroundStyle(s.state == .pending ? .secondary : .primary)
                Text(s.time).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func color(for state: StageState) -> Color {
        switch state {
        case .done:    return .secondary
        case .active:  return .accentColor
        case .pending: return .secondary.opacity(0.4)
        }
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
