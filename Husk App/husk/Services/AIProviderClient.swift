//
//  AIProviderClient.swift
//  husk
//

import Foundation

struct AIProviderConfiguration: Sendable {
    let baseURL: URL
    let apiKey: String

    init(baseURL: URL, apiKey: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> AIProviderConfiguration {
        // Keep the original preference keys so existing Husk installations migrate seamlessly.
        let host = defaults.string(forKey: "ollamaURL") ?? "http://localhost"
        let port = defaults.string(forKey: "ollamaPort") ?? "11434"
        let baseURL = makeBaseURL(host: host, port: port)
            ?? URL(string: "http://localhost:11434")!
        return AIProviderConfiguration(baseURL: baseURL)
    }

    static func makeBaseURL(host: String, port: String) -> URL? {
        var normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else { return nil }

        if !normalizedHost.lowercased().hasPrefix("http://") &&
            !normalizedHost.lowercased().hasPrefix("https://") {
            normalizedHost = "http://" + normalizedHost
        }

        guard var components = URLComponents(string: normalizedHost),
              components.host?.isEmpty == false else {
            return nil
        }

        if !port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let portNumber = Int(port), (1...65535).contains(portNumber) else {
                return nil
            }
            components.port = portNumber
        }

        return components.url
    }
}

struct AIChatRequestMessage: Sendable {
    let role: Role
    let content: String
}

struct AIStreamChunk: Sendable {
    let content: String
    let reasoningContent: String?
    let completionTokens: Int?
}

/// The only AI API surface visible to Husk's app logic.
/// A different provider SDK can be adopted by adding another implementation.
protocol AIProviderClient {
    var provider: Provider { get }

    func isReachable() async -> Bool
    func models() async throws -> [LanguageModel]
    func streamChat(
        model: String,
        messages: [AIChatRequestMessage]
    ) async throws -> AsyncThrowingStream<AIStreamChunk, Error>
}

typealias AIProviderFactory = (AIProviderConfiguration) -> any AIProviderClient
