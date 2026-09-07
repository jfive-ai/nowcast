import Foundation

/// Streaming response collection shared by all HTTP callers. Limits apply to
/// bytes delivered by URLSession (including decompression), not just a server's
/// optional Content-Length. Always cancel the transfer when leaving early.
enum BoundedFetch {
    static let sourceLimit = 8 * 1024 * 1024
    static let llmLimit = 16 * 1024 * 1024
    static let webhookLimit = 64 * 1024

    enum FetchError: Error, LocalizedError, Equatable {
        case responseTooLarge(maxBytes: Int)

        var errorDescription: String? {
            switch self {
            case .responseTooLarge(let limit):
                return "HTTP response exceeds the \(limit)-byte size limit."
            }
        }
    }

    static func data(for request: URLRequest, session: URLSession,
                     maxBytes: Int = sourceLimit) async throws -> (Data, URLResponse) {
        precondition(maxBytes >= 0)
        let collector = Collector(maxBytes: maxBytes)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                collector.start(request: request, session: session, continuation: continuation)
            }
        } onCancel: {
            collector.cancel()
        }
    }

    /// URLSession delivers chunks directly to this per-task delegate. Unlike an
    /// async sequence's producer buffer, this accumulator enforces the ceiling
    /// in the receive callback, even when the consumer is suspended.
    /// All state is protected by `lock`; continuations resume exactly once.
    private final class Collector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let maxBytes: Int
        private var body = Data()
        private var response: URLResponse?
        private var task: URLSessionDataTask?
        private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
        private var finished = false

        init(maxBytes: Int) { self.maxBytes = maxBytes }

        func start(request: URLRequest, session: URLSession,
                   continuation: CheckedContinuation<(Data, URLResponse), Error>) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            let task = session.dataTask(with: request)
            // Unimplemented task delegate callbacks (notably redirects) still
            // forward to the session delegate, preserving OutboundURLPolicy.
            task.delegate = self
            self.task = task
            self.continuation = continuation
            lock.unlock()
            task.resume()
        }

        func cancel() { finish(error: CancellationError()) }

        private func finish(error: Error? = nil) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let continuation = self.continuation
            let task = self.task
            let result: Result<(Data, URLResponse), Error>
            if let error { result = .failure(error) }
            else if let response { result = .success((body, response)) }
            else { result = .failure(URLError(.badServerResponse)) }
            self.continuation = nil
            self.task = nil
            body = Data()
            lock.unlock()
            if error != nil { task?.cancel() }
            continuation?.resume(with: result)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            lock.lock()
            let reject = finished || response.expectedContentLength > Int64(maxBytes)
            if !reject { self.response = response }
            lock.unlock()
            if reject {
                finish(error: FetchError.responseTooLarge(maxBytes: maxBytes))
                completionHandler(.cancel)
            } else {
                completionHandler(.allow)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            // Subtraction avoids overflow for an adversarial chunk length.
            let tooLarge = data.count > maxBytes - body.count
            if !tooLarge { body.append(data) }
            lock.unlock()
            if tooLarge { finish(error: FetchError.responseTooLarge(maxBytes: maxBytes)) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            finish(error: error)
        }
    }
}
