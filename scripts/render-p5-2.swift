#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P5-2 "Entities" sidebar tab with a representative entity
// list + selected timeline. ImageRenderer-based, no app launch required.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = EntitiesSpec()
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
        let url = outDir.appendingPathComponent("p5-2-entity-timeline.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

// MARK: - Spec

struct EntitiesSpec: View {
    let entities: [(name: String, kind: String, symbol: String, count: Int)] = [
        ("Ethereum", "Project", "cube", 28),
        ("EigenLayer", "Project", "cube", 17),
        ("Vitalik Buterin", "Person", "person.circle", 14),
        ("Ethereum Foundation", "Organization", "building.2", 11),
        ("Lido", "Project", "cube", 9),
        ("Pectra", "Project", "cube", 8),
        ("Symbiotic", "Project", "cube", 6),
        ("BIS", "Organization", "building.2", 5),
        ("$ETH", "Topic", "number", 22),
        ("$BTC", "Topic", "number", 7),
    ]
    let timeline: [(topic: String, date: String, headline: String)] = [
        ("ethereum", "May 16",  "Pectra activation window confirmed"),
        ("ethereum", "May 15",  "EF treasury sold 1,000 ETH"),
        ("ethereum", "May 14",  "EIP-7702 inclusion finalized"),
        ("crypto regs", "May 13", "EU MiCA Phase II — ETH staking carve-out"),
        ("ethereum", "May 12",  "Sepolia rehearsal completes"),
        ("ai safety", "May 9",  "VB op-ed: d/acc one year later"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 380)
            Divider()
            detailPane
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                            .frame(height: 24)
                        Text("Filter entities…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .font(.callout)
                    }
                }
                HStack(spacing: 0) {
                    segment("All", selected: true)
                    segment("Person", selected: false)
                    segment("Org", selected: false)
                    segment("Project", selected: false)
                    segment("Topic", selected: false)
                }
            }
            .padding(12)
            Divider()

            ForEach(0..<entities.count, id: \.self) { idx in
                let e = entities[idx]
                HStack {
                    Image(systemName: e.symbol).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.name).font(.callout)
                        Text(e.kind).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(e.count)")
                        .font(.caption).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(idx == 2 ? Color.accentColor.opacity(0.12) : Color.clear)
            }
            Spacer()
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func segment(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.20) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "person.circle")
                    .font(.title2).foregroundStyle(.secondary)
                Text("Vitalik Buterin")
                    .font(.title).bold()
                Text("Person · 14 mentions")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("First seen: Mar 12 · Last seen: today")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Timeline").font(.headline).padding(.top, 6)

            ForEach(0..<timeline.count, id: \.self) { idx in
                let row = timeline[idx]
                HStack(alignment: .top, spacing: 10) {
                    VStack {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                        if idx < timeline.count - 1 {
                            Rectangle().fill(Color.accentColor.opacity(0.25))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(row.topic).font(.callout).bold()
                            Text("·").foregroundStyle(.secondary)
                            Text(row.date).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(row.headline).font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in
    renderAll()
    exit(0)
}
_ = task
RunLoop.main.run()
