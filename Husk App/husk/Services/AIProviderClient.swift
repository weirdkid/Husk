//
//  AIProviderClient.swift
//  husk
//

import Foundation

struct AIProviderConfiguration: Sendable {
    static let serviceURLPreferenceKey = "aiServiceURL"
    static let defaultServiceURL = "http://localhost:8080/v1"

    let baseURL: URL
    let apiKey: String

    init(baseURL: URL, apiKey: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> AIProviderConfiguration {
        if let storedURL = defaults.string(forKey: serviceURLPreferenceKey),
           let baseURL = makeBaseURL(from: storedURL) {
            return AIProviderConfiguration(baseURL: baseURL)
        }

        let baseURL = migrateLegacyConnectionSettings(defaults)
            ?? URL(string: defaultServiceURL)!
        defaults.set(baseURL.absoluteString, forKey: serviceURLPreferenceKey)
        return AIProviderConfiguration(baseURL: baseURL)
    }

    static func makeBaseURL(from value: String) -> URL? {
        var normalizedURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedURL.isEmpty else { return nil }

        if !normalizedURL.lowercased().hasPrefix("http://") &&
            !normalizedURL.lowercased().hasPrefix("https://") {
            normalizedURL = "http://" + normalizedURL
        }

        guard let components = URLComponents(string: normalizedURL),
              components.host?.isEmpty == false,
              components.scheme == "http" || components.scheme == "https" else {
            return nil
        }

        return components.url
    }

    private static func migrateLegacyConnectionSettings(_ defaults: UserDefaults) -> URL? {
        guard let legacyHost = defaults.string(forKey: "ollamaURL"),
              var baseURL = makeBaseURL(from: legacyHost),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // Only apply the old port field when the URL itself did not contain one.
        if components.port == nil,
           let legacyPort = defaults.string(forKey: "ollamaPort"),
           let portNumber = Int(legacyPort),
           (1...65535).contains(portNumber) {
            components.port = portNumber
            baseURL = components.url ?? baseURL
        }

        return baseURL
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
