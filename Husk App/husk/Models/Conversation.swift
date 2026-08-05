//
//  Conversation.swift
//  husk
//
//  Created by Nathan Ellis on 30/05/2025.
//
import SwiftData
import Foundation

@Model
final class Conversation {
    var id: UUID = UUID()
    var title: String = ""
    var lastActivityDate: Date = Date()
    var modelNameUsed: String?
    var userTurnCount: Int = 0
    var lastTitleEvaluationTurn: Int = 0
    var titleWasManuallyEdited: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage]? = []
    
    init(id: UUID = UUID(),
         title: String? = nil,
         lastActivityDate: Date = Date(),
         modelNameUsed: String? = nil,
         userTurnCount: Int = 0,
         lastTitleEvaluationTurn: Int = 0,
         titleWasManuallyEdited: Bool = false,
         messages: [ChatMessage]? = []) {
        self.id = id
        self.lastActivityDate = lastActivityDate
        self.modelNameUsed = modelNameUsed
        self.userTurnCount = userTurnCount
        self.lastTitleEvaluationTurn = lastTitleEvaluationTurn
        self.titleWasManuallyEdited = titleWasManuallyEdited
        self.messages = messages

        if let providedTitle = title, !providedTitle.isEmpty {
            self.title = providedTitle
        } else {
            self.title = "New Chat \(id.uuidString.prefix(4))"
        }
    }

    @MainActor
    func addMessage(_ message: ChatMessage, modelContext: ModelContext) {
        message.conversation = self
        if self.messages == nil {
            self.messages = []
        }
        self.messages?.append(message)
        lastActivityDate = Date()
    }

    @MainActor
    func updateTitleIfNeeded() {
        guard title.isEmpty || title.starts(with: "New Chat") else {
            return
        }

        let firstUserMessage = messages?
            .filter { Role(rawValue: $0.roleValue) == .user && !$0.content.isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
            .first

        if let firstUserMessage {
            let trimmedContent = firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let potentialTitle = String(trimmedContent.prefix(35))
            if !potentialTitle.isEmpty {
                self.title = potentialTitle + (trimmedContent.count > 35 ? "..." : "")
            }
        } else if (messages ?? []).isEmpty {
           self.title = "New Chat"
        }
    }
}
