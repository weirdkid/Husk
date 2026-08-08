//
//  SwiftOpenAIProvider.swift
//  CompanionConnect
//

import Foundation
import SwiftOpenAI

/// Adapts SwiftOpenAI to Companion Connect's provider-neutral API.
final class SwiftOpenAIProvider: AIProviderClient {
    let provider: Provider = .openAICompatible

    private let service: any OpenAIService
    private let session: URLSession
    private let chatCompletionsURL: URL
    private let apiKey: String

    init(configuration: AIProviderConfiguration) {
        let baseURL = Self.normalizedBaseURL(configuration.baseURL)
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = configuration.responseTimeout
        let session = URLSession(configuration: sessionConfiguration)
        let httpClient = URLSessionHTTPClientAdapter(urlSession: session)
        self.session = session
        self.chatCompletionsURL = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
        self.apiKey = configuration.apiKey
        self.service = OpenAIServiceFactory.service(
            apiKey: configuration.apiKey,
            overrideBaseURL: baseURL.absoluteString,
            overrideVersion: "v1",
            httpClient: httpClient
        )
    }

    func isReachable() async -> Bool {
        do {
            _ = try await service.listModels()
            return true
        } catch {
            return false
        }
    }

    func models() async throws -> [LanguageModel] {
        try await service.listModels().data
            .map { LanguageModel(name: $0.id, provider: provider) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func streamChat(
        model: String,
        messages: [AIChatRequestMessage],
        store: Bool?
    ) async throws -> AsyncThrowingStream<AIStreamChunk, Error> {
        let payload = CompanionChatRequest(
            model: model,
            messages: messages.map {
                .init(role: $0.role.rawValue, content: $0.content)
            },
            store: store,
            clientContext: .current
        )
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return AsyncThrowingStream { continuation in
            let forwardingTask = Task {
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase

                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        guard line.hasPrefix("data:") else { continue }
                        let dataString = line
                            .dropFirst(5)
                            .trimmingCharacters(in: .whitespaces)
                        guard dataString != "[DONE]" else { break }
                        guard let data = dataString.data(using: .utf8) else { continue }

                        let response = try decoder.decode(
                            CompanionStreamResponse.self,
                            from: data
                        )
                        continuation.yield(
                            AIStreamChunk(
                                content: response.choices?.first?.delta?.content ?? "",
                                reasoningContent: response.choices?.first?.delta?.reasoningContent,
                                completionTokens: response.usage?.completionTokens
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                forwardingTask.cancel()
            }
        }
    }

    private struct CompanionChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let store: Bool?
        let stream = true
        let streamOptions = StreamOptions(includeUsage: true)
        let clientContext: ClientContext

        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct StreamOptions: Encodable {
            let includeUsage: Bool
        }

        struct ClientContext: Encodable {
            let timezone: String
            let locale: String

            static var current: ClientContext {
                ClientContext(
                    timezone: TimeZone.autoupdatingCurrent.identifier,
                    locale: Locale.autoupdatingCurrent.identifier
                        .replacingOccurrences(of: "_", with: "-")
                )
            }
        }

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case store
            case stream
            case streamOptions = "stream_options"
            case clientContext = "client_context"
        }
    }

    private struct CompanionStreamResponse: Decodable {
        let choices: [Choice]?
        let usage: Usage?

        struct Choice: Decodable {
            let delta: Delta?
        }

        struct Delta: Decodable {
            let content: String?
            let reasoningContent: String?
        }

        struct Usage: Decodable {
            let completionTokens: Int?
        }
    }

    /// SwiftOpenAI appends its configured API version, so accept either a host
    /// URL or a URL ending in `/v1` without producing `/v1/v1`.
    private static func normalizedBaseURL(_ url: URL) -> URL {
        guard url.pathComponents.last?.lowercased() == "v1" else {
            return url
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var path = url.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        path.removeLast(3) // Remove the trailing `/v1`; SwiftOpenAI adds it back.
        components?.path = path
        return components?.url ?? url
    }
}
