//
//  huskApp.swift
//  husk
//
//  Created by Nathan Ellis on 30/05/2025.
//

// huskApp.swift
import SwiftUI
import SwiftData

@main
struct huskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var chatManager: ChatManager
    @StateObject private var speechManager: SpeechToTextManager
    @StateObject private var attachmentManager: AttachmentManager
    
    let modelContainer: ModelContainer
    let storeIdentifier = "HuskMainStore"

    init() {
        let schema = Schema([
            Conversation.self,
            ChatMessage.self,
        ])
        let modelConfiguration = ModelConfiguration(
            storeIdentifier,
            schema: schema,
            isStoredInMemoryOnly: false
        )
        print("SwiftData: Initializing local cache for server-backed history.")

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContainer = container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        let mainContext = self.modelContainer.mainContext
        let manager = ChatManager(modelContext: mainContext)
        _chatManager = StateObject(wrappedValue: manager)
        
        _speechManager = StateObject(wrappedValue: SpeechToTextManager())
        _attachmentManager = StateObject(wrappedValue: AttachmentManager())
    }

    var body: some Scene {
        WindowGroup {
            Splash()
                .environmentObject(chatManager)
                .environmentObject(speechManager)
                .environmentObject(attachmentManager)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, newPhase in
                    chatManager.scenePhaseDidChange(to: newPhase)
                    guard newPhase == .active else { return }
                    Task {
                        await chatManager.synchronizeConversationHistory()
                    }
                }
        }
        .modelContainer(self.modelContainer)
    }
}
