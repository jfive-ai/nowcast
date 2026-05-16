#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders representative screenshots of every Phase-4 surface to PNG using
// SwiftUI ImageRenderer + AppKit. No TCC permission needed — we render the
// view tree directly instead of capturing the display.
//
// Run:  ./scripts/render-screenshots.swift  (or: xcrun swift run-script ...)
// Output: $PWD/screenshots/p4-*.png

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let views: [(String, AnyView, CGSize)] = [
        ("p4-settings-pipeline", AnyView(PipelineSettingsSpec()), CGSize(width: 600, height: 560)),
        ("p4-analytics", AnyView(AnalyticsSpec()), CGSize(width: 720, height: 800)),
        ("p4-source-health", AnyView(SourceHealthSpec()), CGSize(width: 720, height: 620)),
        ("p4-search", AnyView(SearchSpec()), CGSize(width: 420, height: 540)),
        ("p4-report-view", AnyView(ReportSpec()), CGSize(width: 820, height: 800)),
    ]
    for (name, view, size) in views {
        let wrapped = view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .foregroundStyle(Color(nsColor: .labelColor))
        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 2.0
        guard let cgImage = renderer.cgImage else {
            FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
            continue
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            let url = outDir.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print("wrote \(url.path) (\(png.count) bytes)")
        }
    }
}

// MARK: - Specification views

/// Visual spec of Settings → Pipeline section that P4-9 + P4-10 + P4-11 add.
struct PipelineSettingsSpec: View {
    var body: some View {
        // No ScrollView — ImageRenderer doesn't render off-screen content
        // inside a ScrollView. We size the frame externally.
        VStack(alignment: .leading, spacing: 12) {
                Text("Settings").font(.title).bold()
                Card(title: "Pipeline") {
                    Toggle(isOn: .constant(true)) {
                        VStack(alignment: .leading) {
                            Text("Query rewriting").font(.body)
                            Text("Fan out 3+ word topics into 2-4 sub-queries. One extra cheap LLM call per run; better recall.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: .constant(false)) {
                        VStack(alignment: .leading) {
                            Text("Contradiction detection").font(.body)
                            Text("Second-pass scan for cross-source disagreement (numbers, dates, entities). One extra LLM call per brief.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Run self-check") {}
                        Label("PASS", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                    }
                    Text("✓ P4-1: 2 items linked\n✓ P4-2: 2 clusters persisted\n✓ P4-4: feedback round-trip\n✓ P4-5: source_run row recorded\n✓ P4-6: FTS finds new report\n✓ P4-7: speech script clean")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                }
                Card(title: "Storage") {
                    row("Total report size", "1.2 MB")
                    row("Reports stored", "26")
                    row("Items persisted", "142")
                    row("Report ↔ item links", "84")
                }
        }
        .padding()
    }
    func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }
}

struct AnalyticsSpec: View {
    let costs: [(String, Double)] = [("May 10",0.04),("May 11",0.07),("May 12",0.03),("May 13",0.11),("May 14",0.08),("May 15",0.06),("May 16",0.05)]
    let topics: [(String, Int)] = [("ethereum",18),("rust async",11),("ai safety",9),("crypto regs",7),("ml infra",5)]
    let funnel: [(String, Int)] = [("Returned",132),("Fresh",47),("In report",29)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Analytics").font(.title2).bold()
                    Spacer()
                    Text("Last 30 days").font(.caption).foregroundStyle(.secondary)
                }
                Card(title: "Cost trend (USD)") {
                    Chart {
                        ForEach(costs, id: \.0) { pt in
                            LineMark(x: .value("day", pt.0), y: .value("usd", pt.1))
                            AreaMark(x: .value("day", pt.0), y: .value("usd", pt.1))
                                .foregroundStyle(Color.accentColor.opacity(0.15))
                        }
                    }.frame(height: 160)
                }
                Card(title: "Top topics") {
                    Chart {
                        ForEach(topics, id: \.0) { t in
                            BarMark(x: .value("count", t.1), y: .value("topic", t.0))
                        }
                    }.frame(height: 180)
                }
            Card(title: "Freshness funnel") {
                Chart {
                    ForEach(funnel, id: \.0) { stage in
                        BarMark(x: .value("stage", stage.0), y: .value("items", stage.1))
                    }
                }.frame(height: 160)
            }
        }
        .padding()
    }
}

struct SourceHealthSpec: View {
    let rows: [(String, Double, Int, Int, String?)] = [
        ("HN", 1.0, 132, 47, nil),
        ("Reddit", 0.91, 56, 18, nil),
        ("RSS", 0.85, 40, 12, nil),
        ("Brave", 0.78, 28, 8, nil),
        ("YouTube ch.", 0.95, 22, 7, nil),
        ("News", 0.66, 19, 5, "Google News RSS 503"),
        ("Nitter", 0.12, 0, 0, "mirror unreachable: timeout"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Source health").font(.title2).bold()
                Spacer()
                Text("Last 30 days").font(.caption).foregroundStyle(.secondary)
            }
            Text("Success rate").font(.headline)
            Chart {
                ForEach(rows, id: \.0) { r in
                    BarMark(x: .value("src", r.0), y: .value("ok", r.1 * 100))
                        .foregroundStyle(r.1 >= 0.9 ? Color.green : (r.1 >= 0.5 ? Color.yellow : Color.red))
                        .annotation(position: .top) { Text("\(Int(r.1 * 100))%").font(.caption2).foregroundStyle(.secondary) }
                }
            }.frame(height: 130).chartYScale(domain: 0...110)
            Text("Items: returned vs fresh").font(.headline)
            Chart {
                ForEach(rows, id: \.0) { r in
                    BarMark(x: .value("src", r.0), y: .value("ret", r.2)).foregroundStyle(.gray.opacity(0.35))
                    BarMark(x: .value("src", r.0), y: .value("fresh", r.3)).foregroundStyle(Color.accentColor)
                }
            }.frame(height: 130)
            Text("Last error").font(.headline)
            ForEach(rows, id: \.0) { r in
                HStack {
                    Text(r.0).bold().frame(width: 100, alignment: .leading)
                    if let err = r.4 {
                        Text(err).foregroundStyle(.red).lineLimit(1).font(.caption)
                    } else {
                        Text("OK").foregroundStyle(.green).font(.caption)
                    }
                    Spacer()
                }
            }
        }.padding()
    }
}

struct SearchSpec: View {
    let hits: [(String, String)] = [
        ("ethereum staking liquid restaking eigenlayer",
         "...EigenLayer reached <<3.2B>> in TVL across <<liquid restaking>>..."),
        ("rust async runtime",
         "...benchmarks compare <<tokio>> and <<smol>> on <<async>> task spawning..."),
        ("AI regulation EU",
         "...the EU AI Act enforcement timeline accelerates with <<2026>> compliance deadlines..."),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("eigenlayer").foregroundStyle(.primary)
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(hits.enumerated()), id: \.offset) { idx, hit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.0).bold()
                        Text(highlight(hit.1))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if idx < hits.count - 1 { Divider() }
                }
            }
            .padding(12)
            Spacer()
        }
    }
    func highlight(_ s: String) -> AttributedString {
        var out = AttributedString()
        var rem = Substring(s)
        while let open = rem.range(of: "<<") {
            out += AttributedString(rem[..<open.lowerBound])
            rem = rem[open.upperBound...]
            if let close = rem.range(of: ">>") {
                var hl = AttributedString(rem[..<close.lowerBound])
                hl.foregroundColor = .accentColor
                hl.inlinePresentationIntent = .stronglyEmphasized
                out += hl
                rem = rem[close.upperBound...]
            } else { out += AttributedString(rem); rem = Substring(); break }
        }
        out += AttributedString(rem)
        return out
    }
}

struct ReportSpec: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack { Spacer()
                    Label("Play", systemImage: "play").foregroundStyle(.blue)
                    Label("👍", systemImage: "hand.thumbsup").foregroundStyle(.secondary)
                    Label("👎", systemImage: "hand.thumbsdown").foregroundStyle(.secondary)
                    Label("⚠", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    Label("Copy", systemImage: "doc.on.doc")
                    Label("Export", systemImage: "square.and.arrow.up")
                }.padding(.bottom, 4)
                Text("ethereum staking").font(.largeTitle).bold()
                Text("May 16, 2026 · 7:42 AM · 24h window · 14 items").font(.caption).foregroundStyle(.secondary)
                Text("OpenAI · gpt-4o-mini · 3.1k tok · ~$0.012").font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("⚠ Sources disagree").font(.title2).bold()
                Text("- 🔴 Numeric: \"IBIT outflow >$80M\" vs \"IBIT outflow <$50M\"\n- 🟡 Date: \"Pectra Oct 7\" vs \"Pectra late October\"")
                Text("What's new since last brief").font(.title2).bold().padding(.top, 4)
                Text("- 🆕 Liquid restaking TVL milestone\n- 🔁 ETH ETF flows\n- 💤 No longer in view — Layer-2 fees")
                Text("TL;DR").font(.title2).bold().padding(.top, 4)
                Text("- ETH ETF redemptions hit one-week record outflow led by IBIT and FBTC.\n- Pectra hard-fork activation window confirmed for early October.\n- Liquid restaking TVL crossed 3.2B across major operators.")
                Text("Stories").font(.title2).bold().padding(.top, 4)
                Text("ETH ETF redemption week").font(.headline)
                Text("Spot ETH ETFs saw a record one-week outflow led by IBIT and FBTC, with EZBC staying flat.").font(.body).foregroundStyle(.secondary)
                Divider().padding(.top, 8)
                Text("Clusters").font(.headline)
            HStack {
                Text("ETH ETF redemption week").bold()
                Spacer()
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Image(systemName: "hand.thumbsup.fill").foregroundStyle(.green)
                Image(systemName: "hand.thumbsdown").foregroundStyle(.secondary)
                Image(systemName: "eye.slash").foregroundStyle(.secondary)
            }.padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
        }
        .padding(20)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }
}

// Charts framework
import Charts

// MARK: - Driver

_ = NSApplication.shared
let task = Task { @MainActor in
    renderAll()
    exit(0)
}
_ = task
RunLoop.main.run()
