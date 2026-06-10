import Foundation
import NaturalLanguage

/// Local, on-device sentence embedder. Wraps Apple's
/// `NLEmbedding.sentenceEmbedding(for: .english)` — runs entirely on the
/// user's machine with zero network calls and no API key.
///
/// Returns nil when the OS doesn't ship an English sentence embedding for
/// the current locale build; callers should treat that as "semantic search
/// unavailable" and fall back to keyword (FTS) search.
final class ReportEmbedder {
    /// Process-wide shared embedder. `NLEmbedding.sentenceEmbedding` loads
    /// ~tens of MB of model data the first time it's resolved, so we keep
    /// one instance alive for the app's lifetime instead of re-resolving
    /// per report.
    static let shared = ReportEmbedder()

    private let embedding: NLEmbedding?
    /// `NLEmbedding` is not thread-safe: concurrent `vector(for:)` calls
    /// (e.g. the detached launch-time backfill racing the pipeline's
    /// save-time embed) crash inside CoreNLP/BNNS. All access is
    /// serialized through this lock.
    private let lock = NSLock()

    init() {
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    /// True iff the OS provided an English sentence embedding. Lets the UI
    /// hide the semantic-search affordance with a clear empty-state instead
    /// of failing silently when the model is absent.
    var isAvailable: Bool { embedding != nil }

    /// Embed `text` to a fixed-length vector. The exact dimensionality is
    /// model-defined and stable for a given OS version — we don't depend on
    /// it. Returns nil for empty input or when the embedder is unavailable.
    func embed(_ text: String) -> [Float]? {
        guard let embedding else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let vector = embedding.vector(for: trimmed) else { return nil }
        return vector.map { Float($0) }
    }

    /// Cosine similarity in [-1, +1]. Higher is more similar. Defensive
    /// against zero-length vectors (returns 0).
    static func similarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var na: Double = 0
        var nb: Double = 0
        for i in 0..<a.count {
            let av = Double(a[i])
            let bv = Double(b[i])
            dot += av * bv
            na += av * av
            nb += bv * bv
        }
        let denom = (na.squareRoot()) * (nb.squareRoot())
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    /// Serialize a Float32 vector to little-endian `Data` for SQLite BLOB
    /// storage. Stable across architectures: we always write LE bytes.
    static func encode(_ vector: [Float]) -> Data {
        var data = Data(capacity: vector.count * MemoryLayout<Float>.size)
        for value in vector {
            var le = value.bitPattern.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Inverse of `encode`. Returns nil for byte counts that aren't a
    /// multiple of 4 (corrupt row).
    static func decode(_ data: Data) -> [Float]? {
        guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        var out: [Float] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let start = i * MemoryLayout<Float>.size
            let bits = data.withUnsafeBytes { raw -> UInt32 in
                var v: UInt32 = 0
                for byte in 0..<MemoryLayout<UInt32>.size {
                    v |= UInt32(raw[start + byte]) << (8 * byte)
                }
                return v
            }
            out.append(Float(bitPattern: UInt32(littleEndian: bits)))
        }
        return out
    }

    /// Compact input text for a report: topic + smart title (if any) +
    /// up-to-N markdown characters. Embeds enough signal to discriminate
    /// between briefs without dragging in noisy boilerplate.
    static func makeIndexText(topic: String, title: String?, markdown: String) -> String {
        let head = [title, topic].compactMap { $0 }.joined(separator: " — ")
        let bodySlice = String(markdown.prefix(1500))
        return head + "\n" + bodySlice
    }
}
