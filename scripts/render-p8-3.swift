#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit -framework Charts
// Renders the P8-3 sentiment-trend chart for a per-preset view, plus the
// inline sentiment indicator that sits above the brief metadata row.

import SwiftUI
import AppKit
import Charts

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = SentimentSpec()
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
        let url = outDir.appendingPathComponent("p8-3-sentiment-trend.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct SentimentSpec: View {
    struct Point { let day: Int; let sentiment: Double; let rationale: String }
    let series: [Point] = [
        Point(day: 0,  sentiment:  0.42, rationale: "EigenLayer interop shipped"),
        Point(day: 1,  sentiment:  0.18, rationale: "EF treasury cautious"),
        Point(day: 2,  sentiment: -0.30, rationale: "Validator slashing fears"),
        Point(day: 3,  sentiment: -0.55, rationale: "ETF outflows spike"),
        Point(day: 4,  sentiment: -0.10, rationale: "Solana ETF talk softens"),
        Point(day: 5,  sentiment:  0.32, rationale: "Pectra activation confirmed"),
        Point(day: 6,  sentiment:  0.62, rationale: "Restaking TVL ATH"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 240)
            Divider()
            chartPane
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Nowcast").font(.headline); Spacer() }.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("ETH daily").font(.callout).bold()
                Text("7 briefs · weekly digest on").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.18))
            VStack(alignment: .leading, spacing: 4) {
                Text("AI safety").font(.callout)
                Text("12 briefs · daily").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Spacer()
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var chartPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sentiment trend").font(.headline)
                    Text("ETH daily · last 7 briefs").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                legend
            }
            chart
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(color: .green, label: "Bullish")
            legendDot(color: .secondary, label: "Neutral")
            legendDot(color: .red, label: "Bearish")
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series, id: \.day) { p in
                LineMark(
                    x: .value("Day", p.day),
                    y: .value("Sentiment", p.sentiment)
                )
                .foregroundStyle(Color.accentColor)
                AreaMark(
                    x: .value("Day", p.day),
                    yStart: .value("Zero", 0.0),
                    yEnd: .value("Sentiment", p.sentiment)
                )
                .foregroundStyle(p.sentiment >= 0 ? Color.green.opacity(0.20) : Color.red.opacity(0.20))
                PointMark(
                    x: .value("Day", p.day),
                    y: .value("Sentiment", p.sentiment)
                )
                .symbolSize(60)
                .foregroundStyle(p.sentiment >= 0 ? Color.green : Color.red)
            }
            RuleMark(y: .value("Neutral", 0.0))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
        }
        .chartYScale(domain: -1.0...1.0)
        .chartYAxis {
            AxisMarks(values: [-1.0, -0.5, 0.0, 0.5, 1.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(String(format: "%+.1f", d)).font(.caption2)
                    }
                }
            }
        }
        .frame(height: 320)
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
