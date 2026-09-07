#!/usr/bin/env swift
// Editable vector source. Run from the repository root: swift design/render-icons.swift
// The same paths produce SVG masters and asset-catalog PNGs, with no external tools.
import AppKit

struct Ink {
    let hex: String
    var cgColor: CGColor {
        let value = UInt32(hex, radix: 16)!
        return CGColor(srgbRed: Double((value >> 16) & 255) / 255,
                       green: Double((value >> 8) & 255) / 255,
                       blue: Double(value & 255) / 255, alpha: 1)
    }
    static let teal = Ink(hex: "163F42")
    static let paper = Ink(hex: "F6F5ED")
    static let mint = Ink(hex: "AFE6CA")
    static let black = Ink(hex: "000000")
}

enum Segment {
    case move(Double, Double), line(Double, Double)
    case curve(Double, Double, Double, Double, Double, Double)
}

final class Canvas {
    let context: CGContext?
    var elements: [String] = []
    init(context: CGContext? = nil) { self.context = context }

    func roundedRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                     radius: Double, ink: Ink) {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context?.addPath(path)
        context?.setFillColor(ink.cgColor)
        context?.fillPath()
        elements.append("<rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(h)\" rx=\"\(radius)\" fill=\"#\(ink.hex)\"/>")
    }

    func circle(_ x: Double, _ y: Double, radius: Double, ink: Ink) {
        context?.setFillColor(ink.cgColor)
        context?.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        elements.append("<circle cx=\"\(x)\" cy=\"\(y)\" r=\"\(radius)\" fill=\"#\(ink.hex)\"/>")
    }

    func stroke(_ segments: [Segment], width: Double, ink: Ink) {
        let path = CGMutablePath()
        var commands: [String] = []
        for segment in segments {
            switch segment {
            case let .move(x, y):
                path.move(to: CGPoint(x: x, y: y)); commands.append("M\(x) \(y)")
            case let .line(x, y):
                path.addLine(to: CGPoint(x: x, y: y)); commands.append("L\(x) \(y)")
            case let .curve(x1, y1, x2, y2, x, y):
                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
                commands.append("C\(x1) \(y1) \(x2) \(y2) \(x) \(y)")
            }
        }
        context?.addPath(path)
        context?.setStrokeColor(ink.cgColor)
        context?.setLineWidth(width)
        context?.setLineCap(.round)
        context?.setLineJoin(.round)
        context?.strokePath()
        elements.append("<path d=\"\(commands.joined(separator: " "))\" fill=\"none\" stroke=\"#\(ink.hex)\" stroke-width=\"\(width)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
    }

    var svg: String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\">\n" + elements.joined(separator: "\n") + "\n</svg>\n"
    }
}

enum Concept: String, CaseIterable {
    case signal, briefing, focus
}

func draw(_ concept: Concept, on c: Canvas, template: Bool = false) {
    if !template { c.roundedRect(100, 100, 824, 824, radius: 184, ink: .teal) }
    let line: Ink = template ? .black : .paper
    let dot: Ink = template ? .black : .mint
    switch concept {
    case .signal:
        // Three quiet input streams become one focused briefing.
        c.stroke([.move(278, 324), .line(358, 324), .curve(466, 324, 470, 512, 594, 512)], width: 58, ink: line)
        c.stroke([.move(278, 512), .line(594, 512)], width: 58, ink: line)
        c.stroke([.move(278, 700), .line(358, 700), .curve(466, 700, 470, 512, 594, 512)], width: 58, ink: line)
        c.circle(734, 512, radius: 67, ink: dot)
    case .briefing:
        // A compact editorial summary, with the latest item picked out.
        c.stroke([.move(296, 330), .line(580, 330)], width: 68, ink: line)
        c.stroke([.move(296, 512), .line(728, 512)], width: 68, ink: line)
        c.stroke([.move(296, 694), .line(620, 694)], width: 68, ink: line)
        c.circle(732, 330, radius: 58, ink: dot)
    case .focus:
        // An open lens: the useful signal is in focus, the feed stays outside.
        c.stroke([.move(695, 340), .curve(548, 180, 286, 292, 286, 512),
                  .curve(286, 732, 548, 844, 695, 684)], width: 64, ink: line)
        c.circle(550, 512, radius: 83, ink: dot)
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fm = FileManager.default
func write(_ data: Data, to path: String) throws {
    let url = root.appendingPathComponent(path)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}
func png(size: Int, concept: Concept = .signal, template: Bool = false,
         background: Ink? = nil, invert: Bool = false) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: Double(size) / 1024, y: Double(size) / 1024)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    if let background {
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }
    if template {
        // The app tile includes padding; the menu glyph fills its 18-point image.
        context.translateBy(x: -350, y: -338)
        context.scaleBy(x: 1.66, y: 1.66)
    }
    if invert {
        // Draw the alpha mask as white on dark previews, as the menu bar does.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
    }
    draw(concept, on: Canvas(context: context), template: template)
    if invert {
        context.setBlendMode(.sourceIn)
        context.setFillColor(Ink.paper.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        context.endTransparencyLayer()
    }
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}
func json(_ object: Any, to path: String) throws {
    try write(JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), to: path)
}

let catalog = "Nowcast/Resources/Assets.xcassets"
try json(["info": ["author": "xcode", "version": 1]], to: "\(catalog)/Contents.json")
var icons: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "appicon_\(size)x\(size)@\(scale)x.png"
        try write(png(size: size * scale), to: "\(catalog)/AppIcon.appiconset/\(name)")
        icons.append(["filename": name, "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x"])
    }
}
try json(["images": icons, "info": ["author": "xcode", "version": 1]], to: "\(catalog)/AppIcon.appiconset/Contents.json")
var glyphs: [[String: String]] = []
for scale in [1, 2] {
    let name = "menu-bar@\(scale)x.png"
    try write(png(size: 18 * scale, template: true), to: "\(catalog)/MenuBarIcon.imageset/\(name)")
    glyphs.append(["filename": name, "idiom": "mac", "scale": "\(scale)x"])
}
try json(["images": glyphs, "info": ["author": "xcode", "version": 1],
          "properties": ["template-rendering-intent": "template"]], to: "\(catalog)/MenuBarIcon.imageset/Contents.json")
for concept in Concept.allCases {
    let vector = Canvas()
    draw(concept, on: vector)
    try write(Data(vector.svg.utf8), to: "design/\(concept.rawValue).svg")
    try write(png(size: 256, concept: concept), to: "design/\(concept.rawValue).png")
}
let glyph = Canvas()
draw(.signal, on: glyph, template: true)
try write(Data(glyph.svg.utf8), to: "design/menu-bar.svg")
try write(png(size: 144, template: true, background: .paper), to: "design/menu-light.png")
try write(png(size: 144, template: true, background: .teal, invert: true), to: "design/menu-dark.png")
print("Rendered three concepts, ten AppIcon images, and 1x/2x menu template images.")
