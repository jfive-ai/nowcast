import Foundation
import AppKit

/// Pure-logic helpers for converting a Nowcast report into shareable
/// artifacts. UI presentation (save panels, share menus) lives in views;
/// this file only knows how to turn a markdown string into bytes on disk.
enum ReportExporter {
    /// Write the raw markdown body to `url`.
    static func writeMarkdown(_ markdown: String, to url: URL) throws {
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Render the markdown to a paginated PDF at `url`. Uses the same
    /// `AttributedString(markdown:)` pipeline as the email renderer so the
    /// inbox preview, the in-app view, and the PDF all read the same.
    static func writePDF(markdown: String, to url: URL) throws {
        let attr = renderAttributed(markdown: markdown)

        // US Letter, 0.75" margins. NSPrintOperation handles pagination as
        // long as the source view is wider than zero and the textStorage is
        // attached — it walks the layout manager page by page.
        let paperSize = NSSize(width: 612, height: 792)
        let margin: CGFloat = 54
        let textWidth = paperSize.width - margin * 2

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: paperSize.height))
        textView.textStorage?.setAttributedString(attr)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(
            width: textWidth,
            height: .greatestFiniteMagnitude
        )

        let info = NSPrintInfo()
        info.paperSize = paperSize
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url as NSURL

        let op = NSPrintOperation(view: textView, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else {
            throw ExportError.pdfRenderFailed
        }
    }

    private static func renderAttributed(markdown: String) -> NSAttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let parsed = try? AttributedString(markdown: markdown, options: opts) {
            return NSAttributedString(parsed)
        }
        return NSAttributedString(string: markdown)
    }

    /// Default filename for an export: a slugged topic plus the generation
    /// date. No extension — caller appends `.md` / `.pdf`.
    static func defaultBasename(for report: Report) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let date = f.string(from: report.generatedAt)
        let slug = report.topic
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(40)
        let trimmed = slug.isEmpty ? "report" : String(slug)
        return "\(trimmed)-\(date)"
    }
}

enum ExportError: Error, LocalizedError {
    case pdfRenderFailed

    var errorDescription: String? {
        switch self {
        case .pdfRenderFailed: return "Could not render the report as a PDF."
        }
    }
}
