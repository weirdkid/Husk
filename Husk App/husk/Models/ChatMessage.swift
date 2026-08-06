//
//  ChatMessage.swift
//  husk
//
//  Created by Nathan Ellis on 30/05/2025.
//

import SwiftData
import Foundation

@Model
final class ChatMessage {
    var id: UUID = UUID()
    var roleValue: String = ""
    var sortIndex: Int = 0
    var content: String = ""
    var tokensPerSecond: Double? = nil
    var tokensPerSecondIsEstimated: Bool = false
    var attachmentFileNames: [String]?
    var contentForLlm: String = ""
    var timestamp: Date = Date()
    var updatedAt: Date = Date()

    var conversation: Conversation?
    
    var thinkingSteps: String? = nil
    var isShowingThinkingIndicator: Bool = false
    var displayPhase: String = MessageDisplayPhase.pending.rawValue
    

    @Transient var isStreaming: Bool = false

    var role: Role {
        get { Role(rawValue: roleValue) ?? .user }
        set { roleValue = newValue.rawValue }
    }

    init(id: UUID = UUID(),
         role: Role,
         sortIndex: Int = 0,
         content: String = "",
         contentForLlm: String = "",
         attachmentFileNames: [String]? = nil,
         timestamp: Date = Date(),
         updatedAt: Date? = nil,
         conversation: Conversation? = nil,
         isStreaming: Bool = false) {
        self.id = id
        self.roleValue = role.rawValue
        self.sortIndex = sortIndex
        self.content = content
        self.contentForLlm = contentForLlm
        self.attachmentFileNames = attachmentFileNames
        self.timestamp = timestamp
        self.updatedAt = updatedAt ?? timestamp
        self.conversation = conversation
        self.isStreaming = isStreaming
    }

    convenience init(role: Role,
                     typedText: String,
                     attachments: [(fileName: String, fileContent: String)]? = nil,
                     timestamp: Date = Date()) {
        let uiText = typedText
        var llmText = typedText
        var resolvedAttachmentFileNames: [String]? = nil

        if let atts = attachments, !atts.isEmpty {
            resolvedAttachmentFileNames = atts.map { $0.fileName }
            let fullFileTexts = atts.map { "\n\n--- Attached File: \($0.fileName) ---\n\($0.fileContent)" }.joined()
            llmText += fullFileTexts
        }

        self.init(role: role, content: uiText, contentForLlm: llmText, attachmentFileNames: resolvedAttachmentFileNames, timestamp: timestamp)
    }

    convenience init(role: Role, content: String, isStreaming: Bool = false, timestamp: Date = Date()) {
        self.init(role: role, content: content, contentForLlm: content, timestamp: timestamp, isStreaming: isStreaming)
    }

    static func isOrderedBefore(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        if lhs.sortIndex != rhs.sortIndex && (lhs.sortIndex > 0 || rhs.sortIndex > 0) {
            return lhs.sortIndex < rhs.sortIndex
        }
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
