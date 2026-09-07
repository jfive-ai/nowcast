import Foundation

struct TimeoutError: Error, LocalizedError {
    var errorDescription: String? { "The operation timed out." }
}

/// Runs `operation` with a deadline. If it doesn't finish within `seconds`,
/// `onTimeout` is invoked and `TimeoutError` is thrown.
///
/// `onTimeout` exists for waits that don't respond to Swift task cancellation —
/// notably `NWConnection` reads in the SMTP client. The sleeping deadline task
/// can't unblock a stuck `connection.receive`, so the SMTP caller passes
/// `onTimeout: { conn.close() }`; cancelling the connection makes the pending
/// receive error out, which lets the operation task finish and the group drain.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    onTimeout: @escaping @Sendable () -> Void = {},
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            onTimeout()
            throw TimeoutError()
        }
        do {
            guard let result = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return result
        } catch {
            group.cancelAll()
            throw error
        }
    }
}
