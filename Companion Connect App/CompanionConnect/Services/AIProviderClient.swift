//
//  AIProviderClient.swift
//  CompanionConnect
//

import Foundation
import Security

struct AIProviderConfiguration: Sendable {
    static let serviceURLPreferenceKey = "aiServiceURL"
    static let responseTimeoutPreferenceKey = "responseInactivityTimeoutSeconds"
    static let defaultServiceURL = "http://localhost:8080/v1"
    static let defaultResponseTimeout: TimeInterval = 300
    private static let apiKeyService = "com.weirdkid.companionconnect.api-key"
    private static let legacyAPIKeyService = "Husk.CompanionAPIKey"
    private static let apiKeyAccount = "default"

    static var hasConfiguredServiceURL: Bool {
        guard let value = UserDefaults.standard.string(forKey: serviceURLPreferenceKey) else {
            return false
        }
        return makeBaseURL(from: value) != nil
    }

    let baseURL: URL
    let apiKey: String
    let responseTimeout: TimeInterval

    init(
        baseURL: URL,
        apiKey: String = "",
        responseTimeout: TimeInterval = defaultResponseTimeout
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.responseTimeout = responseTimeout
    }

    static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> AIProviderConfiguration {
        let storedTimeout = defaults.integer(forKey: responseTimeoutPreferenceKey)
        let responseTimeout = storedTimeout > 0
            ? TimeInterval(storedTimeout)
            : defaultResponseTimeout
        let apiKey = loadAPIKey()

        if let storedURL = defaults.string(forKey: serviceURLPreferenceKey),
           let baseURL = makeBaseURL(from: storedURL) {
            return AIProviderConfiguration(
                baseURL: baseURL,
                apiKey: apiKey,
                responseTimeout: responseTimeout
            )
        }

        if let migratedURL = migrateLegacyConnectionSettings(defaults) {
            defaults.set(migratedURL.absoluteString, forKey: serviceURLPreferenceKey)
            return AIProviderConfiguration(
                baseURL: migratedURL,
                apiKey: apiKey,
                responseTimeout: responseTimeout
            )
        }

        return AIProviderConfiguration(
            baseURL: URL(string: defaultServiceURL)!,
            apiKey: apiKey,
            responseTimeout: responseTimeout
        )
    }

    static func loadAPIKey() -> String {
        if let value = loadAPIKey(service: apiKeyService) {
            return value
        }

        guard let legacyValue = loadAPIKey(service: legacyAPIKeyService) else {
            return ""
        }

        // Migrate in place without deleting the legacy item. Keeping the old
        // value makes rollback to a backed-up build safe.
        _ = saveAPIKey(legacyValue)
        return legacyValue
    }

    private static func loadAPIKey(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?

        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    @discardableResult
    static func saveAPIKey(_ value: String) -> Bool {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: apiKeyAccount,
        ]

        if normalizedValue.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(normalizedValue.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            return false
        }

        return SecItemAdd(
            query.merging(attributes) { _, new in new } as CFDictionary,
            nil
        ) == errSecSuccess
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

/// The only AI API surface visible to Companion Connect's app logic.
/// A different provider SDK can be adopted by adding another implementation.
protocol AIProviderClient {
    var provider: Provider { get }

    func isReachable() async -> Bool
    func models() async throws -> [LanguageModel]
    func streamChat(
        model: String,
        messages: [AIChatRequestMessage],
        store: Bool?
    ) async throws -> AsyncThrowingStream<AIStreamChunk, Error>
}

typealias AIProviderFactory = (AIProviderConfiguration) -> any AIProviderClient
