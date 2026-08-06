//
//  SwiftOpenAIProvider.swift
//  husk
//

import Foundation
import SwiftOpenAI

/// Adapts SwiftOpenAI to Husk's provider-neutral API.
final class SwiftOpenAIProvider: AIProviderClient {
    let provider: Provider = .openAICompatible

    private let service: any OpenAIService

    init(configuration: AIProviderConfiguration) {
        let baseURL = Self.normalizedBaseURL(configuration.baseURL)
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = configuration.responseTimeout
        let session = URLSession(configuration: sessionConfiguration)
        let httpClient = URLSessionHTTPClientAdapter(urlSession: session)
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
        let parameters = ChatCompletionParameters(
            messages: messages.map {
                ChatCompletionParameters.Message(
                    role: Self.swiftOpenAIRole(for: $0.role),
                    content: .text($0.content)
                )
            },
            model: .custom(model),
            store: store,
            streamOptions: .init(includeUsage: true)
        )
        let upstream = try await service.startStreamedChat(parameters: parameters)

        return AsyncThrowingStream { continuation in
            let forwardingTask = Task {
                do {
                    for try await response in upstream {
                        try Task.checkCancellation()
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

    private static func swiftOpenAIRole(
        for role: Role
    ) -> ChatCompletionParameters.Message.Role {
        switch role {
        case .system: .system
        case .user: .user
        case .assistant: .assistant
        case .tool: .tool
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
