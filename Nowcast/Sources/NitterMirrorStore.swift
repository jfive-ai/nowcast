import Foundation

/// Ordered list of Nitter base URLs, persisted in `UserDefaults`. The
/// `NitterAdapter` walks them in order until one responds; on failure the
/// list rotates so a flaky mirror moves to the back of the queue.
///
/// Mirrors come and go fast — defaults are best-effort and the user is
/// expected to curate the list in Settings → Sources → Nitter mirrors.
@MainActor
final class NitterMirrorStore: ObservableObject {
    static let shared = NitterMirrorStore()

    @Published private(set) var mirrors: [String]

    private let defaults: UserDefaults
    private static let key = "nowcast.nitter.mirrors"

    /// Seeded with one widely-known mirror so first-run isn't a blank screen.
    /// The user is expected to add or replace these.
    static let seedMirrors: [String] = [
        "https://nitter.poast.org",
        "https://nitter.privacydev.net",
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.array(forKey: Self.key) as? [String], !saved.isEmpty {
            self.mirrors = saved
        } else {
            self.mirrors = Self.seedMirrors
        }
    }

    func add(_ url: String) {
        let cleaned = Self.normalize(url)
        guard !cleaned.isEmpty, !mirrors.contains(cleaned) else { return }
        mirrors.append(cleaned)
        save()
    }

    func remove(_ url: String) {
        mirrors.removeAll { $0 == url }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        mirrors.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Promote `url` so it's tried first next time. Called by the adapter
    /// when a mirror succeeds, so good mirrors bubble up.
    func promote(_ url: String) {
        guard let idx = mirrors.firstIndex(of: url), idx > 0 else { return }
        mirrors.remove(at: idx)
        mirrors.insert(url, at: 0)
        save()
    }

    /// Demote `url` to the back of the list after a failure. Skipped when
    /// it's the only mirror, since rotating wouldn't help.
    func demote(_ url: String) {
        guard mirrors.count > 1, let idx = mirrors.firstIndex(of: url) else { return }
        mirrors.remove(at: idx)
        mirrors.append(url)
        save()
    }

    private func save() {
        defaults.set(mirrors, forKey: Self.key)
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("/") { s.removeLast() }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "https://" + s
        }
        return s
    }
}
