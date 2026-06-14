import Foundation

/// A minimal async counting semaphore (no Dispatch / no blocking). Bounds how
/// many tasks run a section concurrently — e.g. transcript scrapes fanned out
/// across many subscribed YouTube channels (prod-33), which would otherwise
/// fire dozens of simultaneous `youtube.com/watch` requests and invite a
/// rate-limit / bot-check.
actor AsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) { available = max(0, count) }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
