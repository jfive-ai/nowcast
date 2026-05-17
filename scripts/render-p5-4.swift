#!/usr/bin/env -S xcrun -sdk macosx swift -framework SwiftUI -framework AppKit
// Renders the P5-4 TopicPresetEditor delivery section with the new
// Webhook row + format picker + test-result chip.

import SwiftUI
import AppKit

@MainActor
func renderAll() {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let view = WebhookEditorSpec()
        .frame(width: 720, height: 720, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
    }
    let bmp = NSBitmapImageRep(cgImage: cg)
    if let png = bmp.representation(using: .png, properties: [:]) {
        let url = outDir.appendingPathComponent("p5-4-webhook-delivery.png")
        try? png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    }
}

struct WebhookEditorSpec: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit preset")
                .font(.largeTitle).bold()

            section("Basics") {
                row("Name", "ETH daily")
                row("Topic / query", "ethereum")
            }
            section("Delivery") {
                toggleRow("macOS notification", on: true)
                toggleRow("Menu bar badge", on: true)
                Divider()
                toggleRow("Webhook (Slack / Discord / generic JSON)", on: true)

                HStack {
                    Text("URL").font(.callout).frame(width: 60, alignment: .leading)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4))
                            .frame(height: 26)
                        Text("https://hooks.slack.com/services/T01/B02/xyz…")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                    }
                }
                HStack {
                    Text("Format").font(.callout).frame(width: 60, alignment: .leading)
                    HStack(spacing: 0) {
                        segment("Slack", selected: true)
                        segment("Discord", selected: false)
                        segment("Generic", selected: false)
                    }
                    .frame(maxWidth: 320)
                }
                HStack {
                    Spacer().frame(width: 60)
                    Button("Send test") {}
                        .controlSize(.small)
                    Label("OK (200)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                }

                Text("Reports always appear in History.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Payload preview
            Text("Slack payload preview")
                .font(.headline).padding(.top, 4)
            Text("""
            {
              "text": "Nowcast: ethereum",
              "blocks": [
                {"type":"header","text":{"type":"plain_text","text":"Nowcast: ethereum"}},
                {"type":"context","elements":[
                  {"type":"mrkdwn","text":"18 items · Today"}
                ]},
                {"type":"section","text":{"type":"mrkdwn","text":"• Pectra window confirmed\\n• Restaking TVL up 4%\\n• EF treasury sold 1,000 ETH"}}
              ]
            }
            """)
            .font(.system(.caption, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
            Text(value)
        }
        .font(.callout)
    }

    private func toggleRow(_ label: String, on: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Toggle("", isOn: .constant(on)).labelsHidden().toggleStyle(.switch)
        }
        .font(.callout)
    }

    private func segment(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08))
    }
}

_ = NSApplication.shared
let task = Task { @MainActor in renderAll(); exit(0) }
_ = task
RunLoop.main.run()
