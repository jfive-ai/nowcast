import Foundation

/// Executable integration checks against URLSession's real streaming bridge.
/// No sockets, credentials, or external services are used.
private final class StreamingProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var sent = 0
    private static let observations = Observations()

    private final class Observations: @unchecked Sendable {
        let lock = NSLock()
        var stoppedCounts: [String: Int] = [:]
        var startedPaths: Set<String> = []
        func markStarted(_ path: String) {
            lock.lock(); defer { lock.unlock() }
            startedPaths.insert(path)
        }
        func hasStarted(_ path: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return startedPaths.contains(path)
        }
        func record(_ path: String, count: Int) {
            lock.lock(); defer { lock.unlock() }
            stoppedCounts[path] = count
        }
        func count(_ path: String) -> Int? {
            lock.lock(); defer { lock.unlock() }
            return stoppedCounts[path]
        }
    }

    static func hasStarted(_ path: String) -> Bool { observations.hasStarted(path) }
    static func stoppedCount(_ path: String) -> Int? { observations.count(path) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.path
        Self.observations.markStarted(path)
        var headers: [String: String] = ["Content-Type": "application/octet-stream"]
        if path == "/declared" { headers["Content-Length"] = "1000000" }
        if path == "/exact" { headers["Content-Length"] = "16" }
        guard let response = HTTPURLResponse(url: url, statusCode: path == "/status" ? 429 : 200,
                                             httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path != "/stalled" { emitNext() }
    }
    private func emitNext() {
        let delay = request.url?.path == "/declared" ? 0.5 : 0.01
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            lock.lock()
            guard !stopped else { lock.unlock(); return }
            sent += 1
            let count = sent
            lock.unlock()
            let path = request.url?.path ?? ""
            if path == "/empty" {
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let body = Data(repeating: 65, count: path == "/exact" ? 16 : 8)
            client?.urlProtocol(self, didLoad: body)
            if ["/small", "/exact", "/status"].contains(path) || count >= 100 {
                client?.urlProtocolDidFinishLoading(self)
            } else {
                emitNext()
            }
        }
    }
    override func stopLoading() {
        lock.lock()
        stopped = true
        let count = sent
        lock.unlock()
        Self.observations.record(request.url?.path ?? "", count: count)
    }
}

@main
private enum BoundedFetchRegression {
    static func main() async throws {
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
            fatalError("Streaming regression timed out")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        func fetch(_ path: String, limit: Int = 16) async throws -> (Data, URLResponse) {
            let request = URLRequest(url: URL(string: "https://fixture.invalid\(path)")!)
            return try await BoundedFetch.data(for: request, session: session, maxBytes: limit)
        }
        let (small, _) = try await fetch("/small")
        precondition(small == Data(repeating: 65, count: 8), "Small body must survive unchanged")
        let (exact, _) = try await fetch("/exact")
        precondition(exact.count == 16, "Exactly-at-cap body must succeed")
        let (empty, _) = try await fetch("/empty", limit: 0)
        precondition(empty.isEmpty, "Zero-byte cap must accept an empty body")
        let (_, status) = try await fetch("/status")
        precondition((status as? HTTPURLResponse)?.statusCode == 429, "HTTP status must reach caller")
        for path in ["/declared", "/streamed", "/zero"] {
            let limit = path == "/zero" ? 0 : 16
            do {
                _ = try await fetch(path, limit: limit)
                fatalError("Oversized body was accepted: \(path)")
            } catch let error as BoundedFetch.FetchError {
                precondition(error == .responseTooLarge(maxBytes: limit))
            }
            for _ in 0..<100 where StreamingProtocol.stoppedCount(path) == nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard let count = StreamingProtocol.stoppedCount(path) else {
                fatalError("Oversized transfer was not cancelled: \(path)")
            }
            precondition(count < 100, "Must cancel before producer completes")
            if path == "/declared" { precondition(count == 0, "Reject Content-Length before body") }
        }
        let task = Task { try await fetch("/stalled") }
        for _ in 0..<100 where !StreamingProtocol.hasStarted("/stalled") {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(StreamingProtocol.hasStarted("/stalled"), "Stalled transport must start")
        task.cancel()
        do {
            _ = try await task.value
            fatalError("Cancelled stalled transfer succeeded")
        } catch is CancellationError {
        } catch let error as URLError {
            precondition(error.code == .cancelled)
        }
        for _ in 0..<100 where StreamingProtocol.stoppedCount("/stalled") == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(StreamingProtocol.stoppedCount("/stalled") != nil,
                     "Task cancellation must stop a stalled transport")
        print("PASS: 8 bounded HTTP streaming regressions")
    }
}
