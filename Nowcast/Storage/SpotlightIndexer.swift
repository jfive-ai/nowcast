import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Pushes report metadata + body into the macOS Spotlight index so the
/// user can find a briefing by phrase from anywhere on their Mac. The
/// markdown file is also referenced as `contentURL`, so a Quick Look
/// preview surfaces the rendered body.
@MainActor
struct SpotlightIndexer {
    static let shared = SpotlightIndexer()

    /// Domain identifier groups all Nowcast items so we can wipe or
    /// rebuild them in one call without touching unrelated indexes.
    private let domain = "com.jfive-ai.nowcast.reports"

    private var index: CSSearchableIndex { .default() }

    /// Add (or replace) a single report in the index.
    func donate(report: Report, markdown: String) {
        let item = makeItem(report: report, markdown: markdown)
        index.indexSearchableItems([item]) { error in
            if let error {
                NSLog("Spotlight donate failed: \(error.localizedDescription)")
            }
        }
    }

    /// Remove a single report by ID. Safe to call for IDs that aren't
    /// indexed — Spotlight just no-ops them.
    func remove(reportIDs: [UUID]) {
        guard !reportIDs.isEmpty else { return }
        let ids = reportIDs.map(\.uuidString)
        index.deleteSearchableItems(withIdentifiers: ids) { error in
            if let error {
                NSLog("Spotlight remove failed: \(error.localizedDescription)")
            }
        }
    }

    /// Wipe everything in our domain. Used as part of a full reindex.
    func removeAll(completion: @escaping () -> Void = {}) {
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { error in
            if let error {
                NSLog("Spotlight wipe failed: \(error.localizedDescription)")
            }
            completion()
        }
    }

    /// Replace the index contents with the given reports. Called once at
    /// launch so Spotlight stays in sync even if the user pruned reports
    /// outside the app or installed a fresh build.
    func reindex(reports: [Report], loadMarkdown: @escaping (Report) -> String) {
        // Snapshot inputs onto the main actor before we hop off it for the
        // wipe + rebuild.
        let snapshot = reports.map { ($0, loadMarkdown($0)) }
        removeAll {
            let items = snapshot.map { (report, md) in
                Self.makeItemStatic(report: report, markdown: md, domain: self.domain)
            }
            guard !items.isEmpty else { return }
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    NSLog("Spotlight reindex failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Item construction

    private func makeItem(report: Report, markdown: String) -> CSSearchableItem {
        Self.makeItemStatic(report: report, markdown: markdown, domain: domain)
    }

    nonisolated private static func makeItemStatic(report: Report,
                                                   markdown: String,
                                                   domain: String) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = report.topic
        attrs.displayName = report.topic
        attrs.contentDescription = snippet(from: markdown)
        attrs.textContent = markdown
        attrs.contentCreationDate = report.generatedAt
        attrs.contentModificationDate = report.generatedAt
        attrs.keywords = [report.topic, report.window.displayName, "Nowcast"]
        attrs.contentURL = AppPaths.reportURL(for: report.markdownPath)

        return CSSearchableItem(
            uniqueIdentifier: report.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attrs
        )
    }

    /// First ~280 characters of the markdown body, with the auto-generated
    /// header stripped so the snippet starts on real content.
    nonisolated private static func snippet(from markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        // Drop the leading "# topic" header + the metadata "_when · window · …_" line.
        var idx = 0
        while idx < lines.count {
            let line = lines[idx].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("# ") || line.hasPrefix("_") {
                idx += 1
            } else {
                break
            }
        }
        let body = lines[idx...]
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(body.prefix(280))
    }
}
