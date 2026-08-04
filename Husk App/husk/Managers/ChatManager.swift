//
//  ChatManager.swift
//  husk
//
//  Created by Nathan Ellis on 30/05/2025.
//
import Foundation
import Combine
import SwiftUI
import SwiftData


@MainActor
class ChatManager: ObservableObject {
    
    private var modelContext: ModelContext
    
    @Published var availableModels: [LanguageModel] = []
    @Published var isLoading: Bool = true
    @Published var isReplying: Bool = false
    
    @Published var reachable: Bool = false
    @Published var errorMessage: String? = nil
    
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    
    @Published var currentStreamingMessageContent: String = ""
    
    private var aiProvider: any AIProviderClient
    private let providerFactory: AIProviderFactory
    
    private var reachabilitySubscription: AnyCancellable?
    private let reachabilityCheckInterval: TimeInterval = 10.0
    private var cancellables = Set<AnyCancellable>()
    
    private var currentStreamingTask: Task<Void, Error>? = nil
    
    private var shouldUseLLMForTitles: Bool {
        UserDefaults.standard.bool(forKey: "useLLMToCreateTitles")
    }

    init(
        modelContext: ModelContext,
        providerFactory: @escaping AIProviderFactory = { SwiftOpenAIProvider(configuration: $0) }
    ) {
        self.modelContext = modelContext
        self.providerFactory = providerFactory
        self.aiProvider = providerFactory(.fromUserDefaults())
        
        Task {
            fetchConversations()
            await refreshModels()
            setupContinuousReachabilityListener()
            if self.activeConversation == nil {
                if self.conversations.isEmpty {
                    self.createNewConversation()
                } else {
                    self.activeConversation = self.conversations.first
                }
            }
        }
    }
    
    private func fetchConversations() {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\Conversation.lastActivityDate, order: .reverse)]
        )
        do {
            self.conversations = try modelContext.fetch(descriptor)
            print("SwiftData: Loaded \(self.conversations.count) conversations.")
        } catch {
            print("SwiftData: Failed to fetch conversations: \(error)")
            self.errorMessage = "Could not load conversations: \(error.localizedDescription)"
            self.conversations = []
        }
    }
    
    private func saveContext() {
        do {
            try modelContext.save()
            print("SwiftData: Context saved.")
        } catch {
            print("SwiftData: Failed to save context: \(error)")
            self.errorMessage = "Could not save changes: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    func updateConnectionSettings() {
        print("ChatManager: Updating connection settings.")
        self.aiProvider = providerFactory(.fromUserDefaults())
        
        self.reachable = false
        self.availableModels = []
        self.isLoading = true
        
        reachabilitySubscription?.cancel()
        cancellables.forEach { $0.cancel() }
        setupContinuousReachabilityListener()
    }

    func testConnection(configuration: AIProviderConfiguration) async -> Bool {
        await providerFactory(configuration).isReachable()
    }
    
    func createNewConversation(modelName: String? = nil) {
        let newConversation = Conversation(
            title: nil,
            lastActivityDate: Date(),
            modelNameUsed: modelName ?? availableModels.first?.name,
            messages: []
        )
        newConversation.updateTitleIfNeeded()
        
        modelContext.insert(newConversation)
        saveContext()
        
        var updatedConversations = self.conversations
        if !updatedConversations.contains(where: { $0.id == newConversation.id }) {
            updatedConversations.insert(newConversation, at: 0)
        }
        self.conversations = updatedConversations.sorted(by: { $0.lastActivityDate > $1.lastActivityDate })
        
        self.activeConversation = newConversation
        
    }
    
    func selectConversation(_ conversation: Conversation) {
        activeConversation = conversation
    }
    
    func deleteConversation(_ conversationToDelete: Conversation) {
        let isActiveBeingDeleted = activeConversation?.id == conversationToDelete.id
        
        modelContext.delete(conversationToDelete)
        saveContext()
        
        withAnimation(.spring()) {
            conversations.removeAll { $0.id == conversationToDelete.id }
            if isActiveBeingDeleted {
                activeConversation = conversations.first
            }
        }
    }
    
    func clearAllConversations() {
        do {
            try modelContext.delete(model: Conversation.self)
            saveContext()
            
            print("SwiftData: All conversations cleared.")
            conversations = []
            activeConversation = nil
            createNewConversation()
        } catch {
            print("SwiftData: Failed to clear all conversations: \(error)")
            errorMessage = "Could not clear all chats: \(error.localizedDescription)"
        }
    }

    
    func setupContinuousReachabilityListener() {
        Task {
            let initialStatus = await self.performProviderReachabilityCheck()
            await MainActor.run {
                self.reachable = initialStatus
                self.isLoading = false
                print("Initial AI provider reachability status: \(self.reachable)")
                self.handleReachabilityChange(status: initialStatus)
            }
        }
        
        Timer.publish(every: reachabilityCheckInterval, on: .main, in: .common)
            .autoconnect()
            .flatMap { [weak self] _ -> AnyPublisher<Bool, Never> in
                guard let self = self else {
                    return Empty(completeImmediately: true).eraseToAnyPublisher()
                }
                return Future<Bool, Never> { promise in
                    Task {
                        let status = await self.performProviderReachabilityCheck()
                        promise(.success(status))
                    }
                }
                .eraseToAnyPublisher()
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReachableStatus in
                guard let self = self else { return }
                self.reachable = isReachableStatus
                print("Periodic AI provider reachability status updated to: \(self.reachable)")
                self.handleReachabilityChange(status: isReachableStatus)
            }
            .store(in: &cancellables)
    }
    
    private func performProviderReachabilityCheck() async -> Bool {
        return await aiProvider.isReachable()
    }
    
    private func handleReachabilityChange(status: Bool) {
        if status {
            if self.availableModels.isEmpty && !self.isLoading {
                print("AI provider became reachable, and models are missing. Refreshing models...")
                Task {
                    await self.refreshModels()
                }
            }
        } else {
            print("AI provider is unreachable.")
        }
    }
    
    func refreshModels() async {
        do {
            self.availableModels = try await aiProvider.models()
        } catch {
            print("Error fetching models: \(error.localizedDescription)")
            self.errorMessage = "Could not fetch models: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func generateAndSetConversationTitle(for conversation: Conversation, usingModel modelName: String) async {
        guard let conversationToUpdate = self.conversations.first(where: { $0.id == conversation.id }),
              conversationToUpdate.title.starts(with: "New Chat") || conversationToUpdate.title.isEmpty else {
            print("Title generation skipped: Conversation already has a custom title or doesn't exist.")
            return
        }
        
        let messagesForTitleContext = (conversationToUpdate.messages ?? [])
            .filter { Role(rawValue: $0.roleValue) != .system }
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(4)
        
        guard messagesForTitleContext.count >= 1 else {
            print("Title generation skipped: Not enough context messages.")
            conversationToUpdate.updateTitleIfNeeded()
            saveContext()
            return
        }
        
        var contextString = "Based on the following conversation excerpt, suggest a very short, concise title (ideally 3-5 words, maximum 7 words). Output ONLY the title itself, with no extra text, quotation marks, or labels like 'Title:'.\n\nExcerpt:\n"
        for message in messagesForTitleContext {
            let rolePrefix = (Role(rawValue: message.roleValue) ?? .user) == .user ? "User:" : "Assistant:"
            contextString += "\(rolePrefix) \(message.content)\n"
        }
        contextString += "\nTitle:"
        
        print("Attempting to generate title with prompt: \(contextString)")
        
        do {
            var generatedTitleChars: [String] = []
            let responseStream = try await aiProvider.streamChat(
                model: modelName,
                messages: [AIChatRequestMessage(role: .user, content: contextString)]
            )
            
            for try await chunk in responseStream {
                generatedTitleChars.append(chunk.content)
            }
            
            var generatedTitle = generatedTitleChars.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            
            if generatedTitle.hasPrefix("\"") && generatedTitle.hasSuffix("\"") {
                generatedTitle = String(generatedTitle.dropFirst().dropLast())
            }
            generatedTitle = generatedTitle.replacingOccurrences(of: "Title:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
            
            
            if !generatedTitle.isEmpty && generatedTitle.lowercased() != "no title" && generatedTitle.lowercased() != "untitled" {
                print("LLM generated title: \(generatedTitle)")
                conversationToUpdate.title = generatedTitle
                conversationToUpdate.lastActivityDate = Date()
                saveContext()
            } else {
                print("LLM returned empty or unsuitable title. Falling back to default title generation.")
                conversationToUpdate.updateTitleIfNeeded()
                saveContext()
            }
        } catch {
            print("Failed to generate title using LLM: \(error). Falling back to default title generation.")
            conversationToUpdate.updateTitleIfNeeded()
            saveContext()
        }
    }
    
    func sendMessage(
        typedText: String,
        attachmentDetails: (fileName: String, fileContent: String)?,
        modelName: String
    ) async throws {
        guard let currentConversation = activeConversation else {
            throw ChatManagerError.noActiveConversation
        }
        
        currentStreamingTask?.cancel()
        
        currentConversation.modelNameUsed = modelName
        currentConversation.lastActivityDate = Date()
        
        
        self.isReplying = true
        self.errorMessage = nil
        
        let userAttachments = attachmentDetails != nil ? [(fileName: attachmentDetails!.fileName, fileContent: attachmentDetails!.fileContent)] : nil
        let userMessage = ChatMessage(role: .user, typedText: typedText, attachments: userAttachments)
        currentConversation.addMessage(userMessage, modelContext: modelContext)
        
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        assistantMessage.thinkingSteps = nil
        assistantMessage.displayPhase = MessageDisplayPhase.pending.rawValue
        currentConversation.addMessage(assistantMessage, modelContext: modelContext)
        
        saveContext()
        
        self.currentStreamingMessageContent = ""
        
        let providerHistory: [AIChatRequestMessage] = (currentConversation.messages ?? []).compactMap { msgModel in
            guard let role = Role(rawValue: msgModel.roleValue) else { return nil }
            // Companion owns system instructions and user identity. Ignore any
            // legacy system messages persisted by earlier Husk versions.
            guard role != .system else { return nil }
            return AIChatRequestMessage(role: role, content: msgModel.contentForLlm)
        }
        
        let streamingTask = Task{
            var isInsideThinkTag = false
            var localAccumulatedThinkContent = ""
            var localAccumulatedAnswerContent = ""
            var hasProcessedThinkBlock = false
            
            var unbatchedChunkBuffer = ""
            let batchThreshold = 30
            var lastUpdateTime = Date()
            let minTimeIntervalForUpdate: TimeInterval = 0.2
            
            var completionTokens: Int?
            var throughputTracker = TokenThroughputTracker()
            
            assistantMessage.isStreaming = true
            
            do {
                let responseStream = try await aiProvider.streamChat(
                    model: modelName,
                    messages: providerHistory
                )
                
                for try await streamedResponse in responseStream {
                    try Task.checkCancellation()

                    throughputTracker.record(
                        content: streamedResponse.content,
                        reasoningContent: streamedResponse.reasoningContent
                    )

                    if let tokenCount = streamedResponse.completionTokens {
                        completionTokens = tokenCount
                    }

                    if let reasoningChunk = streamedResponse.reasoningContent,
                       !reasoningChunk.isEmpty {
                        localAccumulatedThinkContent += reasoningChunk
                        assistantMessage.thinkingSteps = localAccumulatedThinkContent
                        assistantMessage.displayPhase = MessageDisplayPhase.thinking.rawValue
                    }
                    
                    var currentChunkToProcess = streamedResponse.content
                    guard !currentChunkToProcess.isEmpty else {
                        continue
                    }
                    
                    if !hasProcessedThinkBlock {
                        if !isInsideThinkTag {
                            if let thinkOpenRange = currentChunkToProcess.range(of: "<think>") {
                                isInsideThinkTag = true
                                assistantMessage.displayPhase = MessageDisplayPhase.thinking.rawValue
                                assistantMessage.content = ""
                                currentChunkToProcess = String(currentChunkToProcess[thinkOpenRange.upperBound...])
                            }
                        }
                        
                        if isInsideThinkTag {
                            if let thinkCloseRange = currentChunkToProcess.range(of: "</think>") {
                                localAccumulatedThinkContent += currentChunkToProcess[..<thinkCloseRange.lowerBound]
                                isInsideThinkTag = false
                                hasProcessedThinkBlock = true
                                assistantMessage.thinkingSteps = localAccumulatedThinkContent
                                assistantMessage.displayPhase = MessageDisplayPhase.answering.rawValue
                                currentChunkToProcess = String(currentChunkToProcess[thinkCloseRange.upperBound...])
                            } else {
                                localAccumulatedThinkContent += currentChunkToProcess
                                if assistantMessage.displayPhase != MessageDisplayPhase.thinking.rawValue {
                                    assistantMessage.displayPhase = MessageDisplayPhase.thinking.rawValue
                                }
                                currentChunkToProcess = ""
                            }
                        }
                    }
                    
                    if !currentChunkToProcess.isEmpty {
                        if assistantMessage.displayPhase != MessageDisplayPhase.answering.rawValue {
                            assistantMessage.displayPhase = MessageDisplayPhase.answering.rawValue
                        }
                        
                        unbatchedChunkBuffer += currentChunkToProcess
                        let now = Date()
                        
                        if unbatchedChunkBuffer.count >= batchThreshold || now.timeIntervalSince(lastUpdateTime) >= minTimeIntervalForUpdate {
                            localAccumulatedAnswerContent += unbatchedChunkBuffer
                            assistantMessage.content = localAccumulatedAnswerContent
                            self.currentStreamingMessageContent = localAccumulatedAnswerContent
                            unbatchedChunkBuffer = ""
                            lastUpdateTime = now
                        }
                    }
                    
                }
                
                if !unbatchedChunkBuffer.isEmpty {
                    localAccumulatedAnswerContent += unbatchedChunkBuffer
                    await MainActor.run {
                        assistantMessage.content = localAccumulatedAnswerContent
                        self.currentStreamingMessageContent = localAccumulatedAnswerContent
                    }
                }
                
                if let throughput = throughputTracker.result(
                    reportedCompletionTokens: completionTokens
                ) {
                    assistantMessage.tokensPerSecond = throughput.tokensPerSecond
                    assistantMessage.tokensPerSecondIsEstimated = throughput.isEstimated
                    print("Calculated TPS: \(throughput.tokensPerSecond) (estimated: \(throughput.isEstimated))")
                } else {
                    print("Could not calculate TPS because the stream contained no generated text.")
                }
                
                assistantMessage.isStreaming = false
                assistantMessage.displayPhase = MessageDisplayPhase.complete.rawValue
                
                if assistantMessage.content.isEmpty && !localAccumulatedAnswerContent.isEmpty {
                    assistantMessage.content = localAccumulatedAnswerContent
                }
                if (assistantMessage.thinkingSteps ?? "").isEmpty && !localAccumulatedThinkContent.isEmpty {
                    assistantMessage.thinkingSteps = localAccumulatedThinkContent
                }
                currentConversation.lastActivityDate = Date()
                
                self.isReplying = false
                self.currentStreamingMessageContent = ""
                saveContext()
                
                if shouldUseLLMForTitles {
                    let messageCountForTitle = (currentConversation.messages ?? [])
                        .filter { Role(rawValue: $0.roleValue) != .system }
                        .count
                    
                    if (currentConversation.title.starts(with: "New Chat") || currentConversation.title.isEmpty) && messageCountForTitle >= 2 {
                        Task {
                            await generateAndSetConversationTitle(for: currentConversation, usingModel: modelName)
                        }
                    }
                } else {
                    if currentConversation.title.starts(with: "New Chat") || currentConversation.title.isEmpty {
                        currentConversation.updateTitleIfNeeded()
                        saveContext()
                    }
                }
                print("SwiftData: Message stream finished, conversation updated and saved.")
                
            }catch is CancellationError{
                print("Streaming task was cancelled by user.")
                assistantMessage.thinkingSteps = localAccumulatedThinkContent.isEmpty ? nil : localAccumulatedThinkContent
                assistantMessage.content = localAccumulatedAnswerContent + "\n\n*(Response stopped by user)*"
                assistantMessage.isStreaming = false
                assistantMessage.displayPhase = MessageDisplayPhase.complete.rawValue
                self.isReplying = false
                self.currentStreamingMessageContent = ""
                saveContext()
            } catch {
                assistantMessage.thinkingSteps = localAccumulatedThinkContent.isEmpty ? nil : localAccumulatedThinkContent
                assistantMessage.content = localAccumulatedAnswerContent + "\n\n*(Error during response: \(error.localizedDescription))*"
                assistantMessage.isStreaming = false
                assistantMessage.displayPhase = MessageDisplayPhase.complete.rawValue
                self.errorMessage = "AI provider request failed: \(error.localizedDescription)"
                self.isReplying = false
                self.currentStreamingMessageContent = ""
                saveContext()
                throw error
            }
        }
        
        self.currentStreamingTask = streamingTask
        
        do {
            defer {
                Task {
                    await MainActor.run {
                        currentConversation.lastActivityDate = Date()
                        currentConversation.updateTitleIfNeeded()
                        if let conv = self.activeConversation, let lastMessage = conv.messages?.last(where: { $0.id == assistantMessage.id }) {
                            lastMessage.isStreaming = false
                            if lastMessage.displayPhase != MessageDisplayPhase.complete.rawValue {
                                lastMessage.displayPhase = MessageDisplayPhase.complete.rawValue
                            }
                        }
                        self.isReplying = false
                        self.currentStreamingMessageContent = ""
                        self.currentStreamingTask = nil
                    }
                    print("sendMessage finished, context saved, isReplying: \(self.isReplying)")
                }
            }
            
            try await streamingTask.value
        } catch is CancellationError {
            print("sendMessage awaited task was cancelled.")
            if assistantMessage.isStreaming {
                assistantMessage.content += "\n\n*(Operation cancelled)*"
                assistantMessage.isStreaming = false
                assistantMessage.displayPhase = MessageDisplayPhase.complete.rawValue
                saveContext()
            }
            self.isReplying = false
            self.currentStreamingMessageContent = ""
            self.currentStreamingTask = nil
        } catch {
            print("sendMessage awaited task failed with error: \(error)")
            if assistantMessage.isStreaming {
                assistantMessage.content += "\n\n*(Operation failed: \(error.localizedDescription))* "
                assistantMessage.isStreaming = false
                assistantMessage.displayPhase = MessageDisplayPhase.complete.rawValue
                saveContext()
            }
            self.errorMessage = self.errorMessage ?? "Chat request failed: \(error.localizedDescription)"
            self.isReplying = false
            self.currentStreamingMessageContent = ""
            self.currentStreamingTask = nil
            if let chatError = error as? ChatManagerError {
                throw chatError
            } else {
                throw ChatManagerError.requestFailed(underlyingError: error)
            }
        }
    }
    
    @MainActor
    func stopGeneratingResponse() {
        print("Stop generating response called.")
        guard let task = currentStreamingTask, !task.isCancelled else {
            print("No active cancellable task, or task already cancelled.")
            if isReplying {
                isReplying = false
                currentStreamingMessageContent = ""
            }
            return
        }
        task.cancel()
    }
}
