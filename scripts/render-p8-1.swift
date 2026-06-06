#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P8-1 semantic-search surface — keyword/semantic picker plus
// the ranked-similarity result list.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = SemanticSearchSpec()
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
        let url = outDir.appendingPathComponent("p8-1-semantic-search.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct SemanticSearchSpec: View {
    struct Hit { let title: String; let date: String; let score: Double }
    let query = "monetary policy"
    let hits: [Hit] = [
        Hit(title: "Fed signals 50bp cut as inflation cools below 2.4%", date: "May 14, 2026", score: 0.83),
        Hit(title: "Treasury 10y dips on dovish FOMC minutes", date: "May 09, 2026", score: 0.71),
        Hit(title: "ECB stays on hold; Lagarde leaves June door open", date: "May 02, 2026", score: 0.66),
        Hit(title: "ETH staking yield slips as risk-free rate moves",     date: "Apr 27, 2026", score: 0.48),
        Hit(title: "Tariff debate: how much really feeds into PCE?",      date: "Apr 22, 2026", score: 0.41),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            searchPane
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Nowcast").font(.headline); Spacer() }
                .padding(12)
            Divider()
            sidebarRow(icon: "doc.text", label: "History", selected: false)
            sidebarRow(icon: "magnifyingglass", label: "Search", selected: true)
            sidebarRow(icon: "person.2", label: "Entities", selected: false)
            Spacer()
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sidebarRow(icon: String, label: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18)
            Text(label).font(.callout)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private var searchPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            picker
                .padding(.horizontal, 16).padding(.top, 12)

            queryField
                .padding(.horizontal, 16)

            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars").font(.caption).foregroundStyle(Color.accentColor)
                Text("Semantic — local on-device embedding, no API")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(hits.count) matches")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            Divider()

            VStack(spacing: 0) {
                ForEach(0..<hits.count, id: \.self) { i in
                    hitRow(hits[i], highlighted: i == 0)
                    if i < hits.count - 1 { Divider() }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var picker: some View {
        HStack(spacing: 0) {
            segment(label: "Keyword", selected: false)
            segment(label: "Semantic", selected: true)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.35), lineWidth: 0.5)
                )
        )
        .frame(width: 320)
    }

    private func segment(label: String, selected: Bool) -> some View {
        Text(label)
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
            .foregroundStyle(selected ? Color.accentColor : Color(nsColor: .labelColor))
    }

    private var queryField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            Text(query).font(.body)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func hitRow(_ hit: Hit, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.title).font(.body).bold()
                Spacer()
                Text(hit.date).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.18))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: max(2, geo.size.width * hit.score), height: 6)
                }
            }
            .frame(height: 6)
            Text(String(format: "Similarity %.0f%%", hit.score * 100))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(highlighted ? Color.accentColor.opacity(0.06) : Color.clear)
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
