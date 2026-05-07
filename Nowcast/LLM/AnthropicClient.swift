import Foundation

/// Anthropic Messages API client. Calls `POST /v1/messages` with the standard
/// `x-api-key` + `anthropic-version` headers and returns the concatenated
/// text from any `text` blocks in the response.
struct AnthropicClient: LLMClient {
    let providerName = "Anthropic"
    let defaultModel = LLMProvider.anthropic.defaultModel

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private let apiVersion: String

    init(apiKey: String,
         baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
         apiVersion: String = "2023-06-01",
         session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.session = session
    }

    func summarize(prompt: String, model: String?) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        let body = MessagesRequest(
            model: model ?? defaultModel,
            max_tokens: 4096,
            temperature: 0.3,
            messages: [.init(role: "user", content: prompt)]
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("messages"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 60

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
            let parsed = try JSONDecoder().decode(MessagesResponse.self, from: data)
            let text = parsed.content
                .compactMap { $0.type == "text" ? $0.text : nil }
                .joined()
            guard !text.isEmpty else { throw LLMError.emptyResponse }
            return text
        } catch let llmError as LLMError {
            throw llmError
        } catch {
            throw LLMError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Wire types

    private struct MessagesRequest: Encodable {
        let model: String
        let max_tokens: Int
        let temperature: Double
        let messages: [Message]
        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct MessagesResponse: Decodable {
        let content: [Block]
        struct Block: Decodable {
            let type: String
            let text: String?
        }
    }
}
