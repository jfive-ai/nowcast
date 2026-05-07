import Foundation

struct OpenAIClient: LLMClient {
    let providerName = "OpenAI"
    let defaultModel = "gpt-4o-mini"

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    init(apiKey: String,
         baseURL: URL = URL(string: "https://api.openai.com/v1")!,
         session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    func summarize(prompt: String, model: String?) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        let resolvedModel = model ?? defaultModel
        let body = ChatRequest(
            model: resolvedModel,
            messages: [.init(role: "user", content: prompt)],
            temperature: 0.3
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
            let parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = parsed.choices.first?.message.content,
                  !content.isEmpty else {
                throw LLMError.emptyResponse
            }
            let usage = parsed.usage.map {
                LLMUsage(promptTokens: $0.prompt_tokens, completionTokens: $0.completion_tokens)
            }
            return LLMResponse(text: content, model: resolvedModel, usage: usage)
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
        let temperature: Double
        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]
        let usage: Usage?
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
        }
    }
}
