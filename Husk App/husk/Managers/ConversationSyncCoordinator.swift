import Foundation
import SwiftData

private struct PendingConversationDeletion: Codable {
    let id: UUID
    let serverRevision: Int
}

@MainActor
final class ConversationSyncCoordinator {
    private static let cursorKey = "companionConversationSyncCursorV1"
    private static let installationIdKey = "companionInstallationIdV1"
    private static let pendingDeletionsKey = "companionPendingConversationDeletionsV1"
    private static let currentDeviceImportPreparedKey = "companionCurrentDeviceImportPreparedV1"

    private let modelContext: ModelContext
    private let defaults: UserDefaults
    private var configuration: AIProviderConfiguration
    private var scheduledSync: Task<Void, Never>?
    private var isSynchronizing = false

    init(
        modelContext: ModelContext,
        configuration: AIProviderConfiguration,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.configuration = configuration
        self.defaults = defaults
    }

    func updateConfiguration(_ configuration: AIProviderConfiguration) {
        self.configuration = configuration
    }

    func scheduleSync() {
        scheduledSync?.cancel()
        scheduledSync = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }

    func queueDeletion(id: UUID, serverRevision: Int) {
        // A revision of zero means this conversation never reached the server.
        guard serverRevision > 0 else { return }
        var deletions = pendingDeletions
        deletions.removeAll { $0.id == id }
        deletions.append(
            PendingConversationDeletion(
                id: id,
                serverRevision: serverRevision
            )
        )
        savePendingDeletions(deletions)
        scheduleSync()
    }

    func synchronize() async {
        guard !isSynchronizing else { return }
        guard let client = try? ConversationSyncClient(configuration: configuration) else {
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }

        do {
            try prepareCurrentDeviceHistoryIfNeeded()
            try await uploadPendingDeletions(using: client)
            try await uploadDirtyConversations(using: client)

            let cursor = defaults.integer(forKey: Self.cursorKey)
            let response = try await client.changes(since: cursor)
            try apply(response.changes)
            defaults.set(response.cursor, forKey: Self.cursorKey)

            // Applying a remote merge can leave a local conversation dirty.
            try await uploadDirtyConversations(using: client)
            try modelContext.save()
        } catch {
            print("Conversation sync failed: \(error.localizedDescription)")
        }
    }

    private func prepareCurrentDeviceHistoryIfNeeded() throws {
        guard !defaults.bool(forKey: Self.currentDeviceImportPreparedKey) else {
            return
        }

        let conversations = try modelContext.fetch(FetchDescriptor<Conversation>())
        for conversation in conversations where !(conversation.messages ?? []).isEmpty {
            // Explicitly mark existing rows; newly added SwiftData properties
            // are not guaranteed to inherit their declaration default during
            // an in-place schema migration.
            conversation.needsSync = true
        }
        try modelContext.save()
        defaults.set(true, forKey: Self.currentDeviceImportPreparedKey)
    }

    private func uploadPendingDeletions(
        using client: ConversationSyncClient
    ) async throws {
        var remaining: [PendingConversationDeletion] = []
        var firstFailure: Error?

        for deletion in pendingDeletions {
            do {
                try await client.delete(
                    id: deletion.id,
                    baseRevision: deletion.serverRevision > 0
                        ? deletion.serverRevision
                        : nil
                )
            } catch ConversationSyncError.server(statusCode: 409, message: _) {
                // A confirmed local deletion wins over a concurrent remote edit.
                try await client.delete(id: deletion.id, baseRevision: nil)
            } catch {
                remaining.append(deletion)
                firstFailure = firstFailure ?? error
            }
        }

        savePendingDeletions(remaining)
        if let firstFailure {
            // Do not download while a deletion is pending; that could briefly
            // resurrect the server copy in the local cache.
            throw firstFailure
        }
    }

    private func uploadDirtyConversations(
        using client: ConversationSyncClient
    ) async throws {
        let descriptor = FetchDescriptor<Conversation>()
        let conversations = try modelContext.fetch(descriptor)
            .filter { conversation in
                conversation.needsSync && !(conversation.messages ?? []).isEmpty
            }

        for conversation in conversations {
            let remote = makeRemoteConversation(from: conversation)

            do {
                let response = try await client.put(
                    remote,
                    baseRevision: conversation.serverRevision > 0
                        ? conversation.serverRevision
                        : nil,
                    merge: conversation.serverRevision == 0,
                    sourceId: installationId
                )
                apply(response, to: conversation)
            } catch ConversationSyncError.server(statusCode: 409, message: _) {
                // Resolve a rare multi-device race by asking the server to merge
                // stable message IDs, then apply its canonical result locally.
                let response = try await client.put(
                    remote,
                    baseRevision: nil,
                    merge: true,
                    sourceId: installationId
                )
                apply(response, to: conversation)
            }
        }
    }

    private func apply(_ changes: [ConversationChange]) throws {
        let localConversations = try modelContext.fetch(FetchDescriptor<Conversation>())
        var conversationsById = Dictionary(
            uniqueKeysWithValues: localConversations.map { ($0.id, $0) }
        )

        for change in changes {
            if change.deleted {
                if let local = conversationsById.removeValue(forKey: change.id) {
                    modelContext.delete(local)
                }
                continue
            }

            guard let remote = change.conversation else { continue }
            let local = conversationsById[change.id] ?? {
                let conversation = Conversation(
                    id: remote.id,
                    title: remote.title,
                    createdAt: remote.createdAt,
                    lastActivityDate: remote.lastActivityDate,
                    updatedAt: remote.updatedAt,
                    modelNameUsed: remote.modelNameUsed,
                    userTurnCount: remote.userTurnCount,
                    lastTitleEvaluationTurn: remote.lastTitleEvaluationTurn,
                    titleWasManuallyEdited: remote.titleWasManuallyEdited,
                    messages: []
                )
                modelContext.insert(conversation)
                conversationsById[change.id] = conversation
                return conversation
            }()

            apply(
                StoredConversationResponse(
                    conversation: remote,
                    revision: change.revision,
                    conflicts: []
                ),
                to: local
            )
        }
    }

    private func apply(
        _ response: StoredConversationResponse,
        to conversation: Conversation
    ) {
        let remote = response.conversation
        conversation.title = remote.title
        conversation.createdAt = remote.createdAt
        conversation.lastActivityDate = remote.lastActivityDate
        conversation.updatedAt = remote.updatedAt
        conversation.modelNameUsed = remote.modelNameUsed
        conversation.userTurnCount = remote.userTurnCount
        conversation.lastTitleEvaluationTurn = remote.lastTitleEvaluationTurn
        conversation.titleWasManuallyEdited = remote.titleWasManuallyEdited
        conversation.serverRevision = response.revision
        conversation.needsSync = false

        let existingMessages = Dictionary(
            uniqueKeysWithValues: (conversation.messages ?? []).map { ($0.id, $0) }
        )
        let remoteIds = Set(remote.messages.map(\.id))

        for (position, remoteMessage) in remote.messages.enumerated() {
            let message = existingMessages[remoteMessage.id] ?? ChatMessage(
                id: remoteMessage.id,
                role: Role(rawValue: remoteMessage.role) ?? .assistant,
                timestamp: remoteMessage.timestamp,
                conversation: conversation
            )
            if existingMessages[remoteMessage.id] == nil {
                conversation.addMessage(message, modelContext: modelContext)
            }

            message.roleValue = remoteMessage.role
            message.sortIndex = remoteMessage.sortIndex ?? position
            message.content = remoteMessage.content
            message.contentForLlm = remoteMessage.contentForLlm
            message.attachmentFileNames = remoteMessage.attachmentFileNames
            message.thinkingSteps = remoteMessage.thinkingSteps
            message.tokensPerSecond = remoteMessage.tokensPerSecond
            message.tokensPerSecondIsEstimated = remoteMessage.tokensPerSecondIsEstimated
            message.displayPhase = remoteMessage.displayPhase
            message.timestamp = remoteMessage.timestamp
            message.updatedAt = remoteMessage.updatedAt
            message.isStreaming = false
        }

        for message in conversation.messages ?? [] where !remoteIds.contains(message.id) {
            modelContext.delete(message)
        }

        // addMessage updates activity for local sends. Restore the canonical
        // server timestamps after inserting remote messages.
        conversation.lastActivityDate = remote.lastActivityDate
        conversation.updatedAt = remote.updatedAt

        if !response.conflicts.isEmpty {
            print("Conversation migration merged \(response.conflicts.count) message conflict(s).")
        }
    }

    private func makeRemoteConversation(
        from conversation: Conversation
    ) -> RemoteConversation {
        let orderedMessages = (conversation.messages ?? [])
            .sorted(by: ChatMessage.isOrderedBefore)

        return RemoteConversation(
            id: conversation.id,
            title: conversation.title,
            createdAt: conversation.createdAt,
            lastActivityDate: conversation.lastActivityDate,
            updatedAt: conversation.updatedAt,
            modelNameUsed: conversation.modelNameUsed,
            userTurnCount: conversation.userTurnCount,
            lastTitleEvaluationTurn: conversation.lastTitleEvaluationTurn,
            titleWasManuallyEdited: conversation.titleWasManuallyEdited,
            messages: orderedMessages
                .enumerated()
                .map { index, message in
                    RemoteChatMessage(
                        id: message.id,
                        role: message.roleValue,
                        sortIndex: index,
                        content: message.content,
                        contentForLlm: message.contentForLlm,
                        attachmentFileNames: message.attachmentFileNames,
                        thinkingSteps: message.thinkingSteps,
                        tokensPerSecond: message.tokensPerSecond,
                        tokensPerSecondIsEstimated: message.tokensPerSecondIsEstimated,
                        displayPhase: message.displayPhase,
                        timestamp: message.timestamp,
                        updatedAt: message.updatedAt
                    )
                }
        )
    }

    private var installationId: String {
        if let existing = defaults.string(forKey: Self.installationIdKey) {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: Self.installationIdKey)
        return generated
    }

    private var pendingDeletions: [PendingConversationDeletion] {
        guard let data = defaults.data(forKey: Self.pendingDeletionsKey) else {
            return []
        }
        return (try? JSONDecoder().decode(
            [PendingConversationDeletion].self,
            from: data
        )) ?? []
    }

    private func savePendingDeletions(
        _ deletions: [PendingConversationDeletion]
    ) {
        if deletions.isEmpty {
            defaults.removeObject(forKey: Self.pendingDeletionsKey)
        } else if let data = try? JSONEncoder().encode(deletions) {
            defaults.set(data, forKey: Self.pendingDeletionsKey)
        }
    }
}
