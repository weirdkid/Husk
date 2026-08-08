import Foundation

struct RemoteChatMessage: Codable, Sendable {
    let id: UUID
    let role: String
    let sortIndex: Int?
    let content: String
    let contentForLlm: String
    let attachmentFileNames: [String]?
    let thinkingSteps: String?
    let tokensPerSecond: Double?
    let tokensPerSecondIsEstimated: Bool
    let displayPhase: String
    let timestamp: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
        case sortIndex = "sort_index"
        case contentForLlm = "content_for_llm"
        case attachmentFileNames = "attachment_file_names"
        case thinkingSteps = "thinking_steps"
        case tokensPerSecond = "tokens_per_second"
        case tokensPerSecondIsEstimated = "tokens_per_second_is_estimated"
        case displayPhase = "display_phase"
        case updatedAt = "updated_at"
    }
}

struct RemoteConversation: Codable, Sendable {
    let id: UUID
    let title: String
    let createdAt: Date
    let lastActivityDate: Date
    let updatedAt: Date
    let modelNameUsed: String?
    let userTurnCount: Int
    let lastTitleEvaluationTurn: Int
    let titleWasManuallyEdited: Bool
    let messages: [RemoteChatMessage]

    enum CodingKeys: String, CodingKey {
        case id, title, messages
        case createdAt = "created_at"
        case lastActivityDate = "last_activity_date"
        case updatedAt = "updated_at"
        case modelNameUsed = "model_name_used"
        case userTurnCount = "user_turn_count"
        case lastTitleEvaluationTurn = "last_title_evaluation_turn"
        case titleWasManuallyEdited = "title_was_manually_edited"
    }
}

struct StoredConversationResponse: Codable, Sendable {
    let conversation: RemoteConversation
    let revision: Int
    let conflicts: [String]
}

struct ConversationChange: Codable, Sendable {
    let id: UUID
    let revision: Int
    let deleted: Bool
    let conversation: RemoteConversation?
}

struct ConversationChangesResponse: Codable, Sendable {
    let cursor: Int
    let changes: [ConversationChange]
}

private struct ConversationUpsertRequest: Codable {
    let conversation: RemoteConversation
    let baseRevision: Int?
    let merge: Bool
    let sourceId: String

    enum CodingKeys: String, CodingKey {
        case conversation, merge
        case baseRevision = "base_revision"
        case sourceId = "source_id"
    }
}

private struct ConversationDeletionResponse: Codable {
    let id: UUID
    let revision: Int
    let deleted: Bool
}

enum ConversationSyncError: LocalizedError {
    case invalidServiceURL
    case missingAPIKey
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidServiceURL:
            "The Companion service URL is invalid."
        case .missingAPIKey:
            "The Companion API key is missing."
        case .invalidResponse:
            "The Companion history service returned an invalid response."
        case let .server(statusCode, message):
            "Companion history request failed (HTTP \(statusCode)): \(message)"
        }
    }
}

actor ConversationSyncClient {
    private let apiRoot: URL
    private let apiKey: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(configuration: AIProviderConfiguration) throws {
        guard !configuration.apiKey.isEmpty else {
            throw ConversationSyncError.missingAPIKey
        }
        guard let apiRoot = Self.apiRoot(from: configuration.baseURL) else {
            throw ConversationSyncError.invalidServiceURL
        }

        self.apiRoot = apiRoot
        self.apiKey = configuration.apiKey

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = configuration.responseTimeout
        self.session = URLSession(configuration: sessionConfiguration)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func changes(since revision: Int) async throws -> ConversationChangesResponse {
        var components = URLComponents(
            url: conversationsURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "since_revision", value: String(max(0, revision)))
        ]
        guard let url = components?.url else {
            throw ConversationSyncError.invalidServiceURL
        }
        return try await request(url: url, method: "GET")
    }

    func conversation(id: UUID) async throws -> StoredConversationResponse {
        try await request(
            url: conversationsURL.appendingPathComponent(id.uuidString.lowercased()),
            method: "GET"
        )
    }

    func put(
        _ conversation: RemoteConversation,
        baseRevision: Int?,
        merge: Bool,
        sourceId: String
    ) async throws -> StoredConversationResponse {
        let body = ConversationUpsertRequest(
            conversation: conversation,
            baseRevision: baseRevision,
            merge: merge,
            sourceId: sourceId
        )
        return try await request(
            url: conversationsURL.appendingPathComponent(
                conversation.id.uuidString.lowercased()
            ),
            method: "PUT",
            body: encoder.encode(body)
        )
    }

    func delete(id: UUID, baseRevision: Int?) async throws {
        var components = URLComponents(
            url: conversationsURL.appendingPathComponent(id.uuidString.lowercased()),
            resolvingAgainstBaseURL: false
        )
        if let baseRevision {
            components?.queryItems = [
                URLQueryItem(name: "base_revision", value: String(baseRevision))
            ]
        }
        guard let url = components?.url else {
            throw ConversationSyncError.invalidServiceURL
        }
        let _: ConversationDeletionResponse = try await request(
            url: url,
            method: "DELETE"
        )
    }

    private var conversationsURL: URL {
        apiRoot
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("conversations")
    }

    private func request<Response: Decodable>(
        url: URL,
        method: String,
        body: Data? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConversationSyncError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw ConversationSyncError.server(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ConversationSyncError.invalidResponse
        }
    }

    private static func apiRoot(from baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var pathComponents = baseURL.pathComponents.filter { $0 != "/" }
        if pathComponents.last?.lowercased() == "v1" {
            pathComponents.removeLast()
        }
        components?.path = pathComponents.isEmpty
            ? ""
            : "/" + pathComponents.joined(separator: "/")
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }
}
