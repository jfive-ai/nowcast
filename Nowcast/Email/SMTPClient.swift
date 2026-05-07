import Foundation
import Network

/// Minimal SMTP-over-TLS client for sending a single message and quitting.
/// Implicit-TLS only (port 465 / SMTPS) — STARTTLS upgrade on port 587 is
/// not supported because `NWConnection` cannot upgrade an in-flight TCP
/// session to TLS without re-establishing it. Most modern providers
/// (Gmail app passwords, Fastmail, SendGrid, Mailgun, etc.) accept 465.
///
/// This is intentionally narrow: one message, one connection, then QUIT.
/// No connection pooling, no pipelining, no command queueing.
struct SMTPClient {
    struct Config {
        var host: String
        var port: UInt16
        var username: String
        var password: String
        var fromAddress: String
        var fromName: String?
    }

    let config: Config

    /// Send `message` to all `recipients` over a fresh TLS SMTP session.
    /// Throws on any protocol or I/O error; partial sends are not retried.
    func send(message: EmailMessage) async throws {
        let conn = try await SMTPConnection.open(host: config.host, port: config.port)
        defer { conn.close() }

        // 220 banner
        _ = try await conn.expect(code: 220)

        try await conn.send("EHLO nowcast.local\r\n")
        _ = try await conn.expect(code: 250)

        try await conn.send("AUTH LOGIN\r\n")
        _ = try await conn.expect(code: 334)

        try await conn.send(Self.base64(config.username) + "\r\n")
        _ = try await conn.expect(code: 334)

        try await conn.send(Self.base64(config.password) + "\r\n")
        _ = try await conn.expect(code: 235)

        try await conn.send("MAIL FROM:<\(config.fromAddress)>\r\n")
        _ = try await conn.expect(code: 250)

        for rcpt in message.recipients {
            try await conn.send("RCPT TO:<\(rcpt)>\r\n")
            _ = try await conn.expect(code: 250)
        }

        try await conn.send("DATA\r\n")
        _ = try await conn.expect(code: 354)

        let body = Self.buildBody(config: config, message: message)
        try await conn.send(body)
        _ = try await conn.expect(code: 250)

        try await conn.send("QUIT\r\n")
        // Some servers don't send a 221 reply before closing. Don't be picky.
    }

    // MARK: - Message construction

    private static func buildBody(config: Config, message: EmailMessage) -> String {
        let boundary = "nowcast-\(UUID().uuidString)"
        let from = config.fromName.map { "\($0) <\(config.fromAddress)>" } ?? config.fromAddress
        let to = message.recipients.joined(separator: ", ")
        let date = Self.rfc5322Date()

        var body = ""
        body += "From: \(from)\r\n"
        body += "To: \(to)\r\n"
        body += "Subject: \(encodeHeader(message.subject))\r\n"
        body += "Date: \(date)\r\n"
        body += "MIME-Version: 1.0\r\n"
        body += "Content-Type: multipart/alternative; boundary=\"\(boundary)\"\r\n"
        body += "\r\n"

        body += "--\(boundary)\r\n"
        body += "Content-Type: text/plain; charset=UTF-8\r\n"
        body += "Content-Transfer-Encoding: 8bit\r\n\r\n"
        body += dotEscape(message.textBody) + "\r\n"

        body += "--\(boundary)\r\n"
        body += "Content-Type: text/html; charset=UTF-8\r\n"
        body += "Content-Transfer-Encoding: 8bit\r\n\r\n"
        body += dotEscape(message.htmlBody) + "\r\n"

        body += "--\(boundary)--\r\n"
        body += ".\r\n"

        return body
    }

    /// SMTP transparent-dot rule: a line starting with "." in the body
    /// MUST be doubled so the server doesn't treat it as end-of-data.
    private static func dotEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n.", with: "\r\n..")
            .replacingOccurrences(of: "\n.", with: "\n..")
    }

    /// Encode a Subject as RFC 2047 Q-encoded UTF-8 if it contains
    /// non-ASCII characters, otherwise pass through.
    private static func encodeHeader(_ s: String) -> String {
        if s.allSatisfy({ $0.isASCII }) { return s }
        let utf8 = Array(s.utf8)
        var out = "=?UTF-8?Q?"
        for byte in utf8 {
            if byte == 0x20 {
                out.append("_")
            } else if byte > 0x20 && byte < 0x7F && byte != UInt8(ascii: "=") && byte != UInt8(ascii: "?") {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out.append(String(format: "=%02X", byte))
            }
        }
        out.append("?=")
        return out
    }

    private static func base64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
    }

    private static func rfc5322Date() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: Date())
    }
}

struct EmailMessage {
    var recipients: [String]
    var subject: String
    var htmlBody: String
    var textBody: String
}

// MARK: - Connection

/// Thin async wrapper around `NWConnection` with line-based receive.
private actor SMTPConnection {
    private let connection: NWConnection
    private var buffer = Data()

    static func open(host: String, port: UInt16) async throws -> SMTPConnection {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let tls = NWProtocolTLS.Options()
        let params = NWParameters(tls: tls)
        let connection = NWConnection(to: endpoint, using: params)
        let conn = SMTPConnection(connection: connection)
        try await conn.start()
        return conn
    }

    private init(connection: NWConnection) {
        self.connection = connection
    }

    nonisolated func close() {
        connection.cancel()
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resumeIfNeeded { cont.resume() }
                case .failed(let error):
                    gate.resumeIfNeeded { cont.resume(throwing: error) }
                case .cancelled:
                    gate.resumeIfNeeded { cont.resume(throwing: SMTPError.connectionClosed) }
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    func send(_ text: String) async throws {
        let data = Data(text.utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    /// Receive lines until a complete reply is buffered; throw if the
    /// final reply code doesn't match `code`.
    /// SMTP multiline replies repeat the code with "-" then end with " ".
    func expect(code: Int) async throws -> String {
        let response = try await receiveReply()
        guard response.code == code else {
            throw SMTPError.unexpectedReply(expected: code, actual: response.code, message: response.text)
        }
        return response.text
    }

    private struct Reply {
        let code: Int
        let text: String
    }

    private func receiveReply() async throws -> Reply {
        var lines: [String] = []
        while true {
            let line = try await receiveLine()
            lines.append(line)
            // SMTP marks the last line of a multi-line reply with " " after the code.
            if line.count >= 4, line[line.index(line.startIndex, offsetBy: 3)] == " " {
                let code = Int(line.prefix(3)) ?? -1
                let combined = lines.joined(separator: "\n")
                return Reply(code: code, text: combined)
            }
        }
    }

    private func receiveLine() async throws -> String {
        while true {
            if let range = buffer.range(of: Data("\r\n".utf8)) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            // Need more bytes.
            let chunk = try await receiveChunk()
            if chunk.isEmpty { throw SMTPError.connectionClosed }
            buffer.append(chunk)
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if isComplete && (data?.isEmpty ?? true) {
                    cont.resume(returning: Data())
                    return
                }
                cont.resume(returning: data ?? Data())
            }
        }
    }
}

/// Single-shot resume gate used while opening the NWConnection. The state
/// handler fires multiple times on the network queue; we want exactly one
/// continuation resume.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resumeIfNeeded(_ block: () -> Void) {
        lock.lock()
        let alreadyResumed = resumed
        if !alreadyResumed { resumed = true }
        lock.unlock()
        if !alreadyResumed { block() }
    }
}

enum SMTPError: Error, LocalizedError {
    case connectionClosed
    case unexpectedReply(expected: Int, actual: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .connectionClosed:
            return "SMTP connection closed unexpectedly."
        case .unexpectedReply(let expected, let actual, let message):
            return "SMTP expected \(expected), got \(actual): \(message)"
        }
    }
}
