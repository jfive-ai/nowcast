import Foundation

/// Ollama-compatible chat client. Talks to a local Ollama instance (default
/// `http://localhost:11434`) via `POST /api/chat` with `stream: false`.
/// No auth — Ollama is intended to bind to localhost.
struct OllamaClient: LLMClient {
    let providerName = "Ollama"
    let defaultModel = LLMProvider.ollama.defaultModel

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:11434")!,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func summarize(prompt: String, model: String?) async throws -> String {
        let body = ChatRequest(
            model: model ?? defaultModel,
            messages: [.init(role: "user", content: prompt)],
            stream: false,
            options: .init(temperature: 0.3)
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        // Local models can be slow on first load.
        request.timeoutInterval = 180

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.requestFailed(status: -1, body: "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.requestFailed(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        do {
            let parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
            let content = parsed.message.content
            guard !content.isEmpty else { throw LLMError.emptyResponse }
            return content
        } catch let llmError as LLMError {
            throw llmError
        } catch {
            throw LLMError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Wire types

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct Options: Encodable {
            let temperature: Double
        }
    }

    private struct ChatResponse: Decodable {
        let message: Message
        struct Message: Decodable {
            let role: String
            let content: String
        }
    }
}
