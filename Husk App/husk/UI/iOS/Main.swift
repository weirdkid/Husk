//
//  Main.swift
//  husk
//
//  Created by Nathan Ellis on 30/05/2025.
//

import SwiftUI
import MarkdownUI
import Foundation

struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Main View
struct Main: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var speechManager: SpeechToTextManager
    @EnvironmentObject var attachmentManager: AttachmentManager
    @AppStorage(AIProviderConfiguration.serviceURLPreferenceKey) private var configuredServiceURL = ""
    
    @State private var scrollProxy: ScrollViewProxy?
    @State private var messageText = ""
    @State private var chatInputBarHeight: CGFloat = 50
    @State private var showSheet = false
    @State private var showLeftSidebar = false
    @State private var path = NavigationPath()
    @State private var showConnectionRequiredAlert = false
    @State private var selectedMessageID: UUID?
    
    
    private var sidebarWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.85, 300)
    }
    
    private var currentMessages: [ChatMessage] {
        guard let activeConvo = chatManager.activeConversation,
              let msgs = activeConvo.messages else {
            return []
        }
        let sortedMessages = msgs.sorted(by: ChatMessage.isOrderedBefore)
        
        if let firstMessage = sortedMessages.first,
           firstMessage.role == .system {
            return Array(sortedMessages.dropFirst())
        }
        return sortedMessages
    }

    private var activeConversationTitle: String {
        let title = chatManager.activeConversation?.title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !title.starts(with: "New Chat") else {
            return "New Chat"
        }
        return title
    }

    private var hasConfiguredServiceURL: Bool {
        AIProviderConfiguration.makeBaseURL(from: configuredServiceURL) != nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if chatManager.isLoading && hasConfiguredServiceURL {
                    connectingView
                } else if chatManager.reachable {
                    mainView
                } else if !hasConfiguredServiceURL {
                    unconfiguredView
                } else {
                    unreachableView
                }
            }
            .navigationDestination(for: SettingsPath.self) { path in
                ConnectionsView()
            }
            .sheet(isPresented: $showSheet) {
                Settings()
                    .presentationBackground(.ultraThinMaterial)
            }
            .onAppear { speechManager.refreshAvailability() }
            .onChange(of: chatManager.activeConversation) {
                selectedMessageID = nil
                scrollToLastMessage()
            }
            .alert("Set Up a Connection", isPresented: $showConnectionRequiredAlert) {
                Button("Open Settings") {
                    path.append(SettingsPath.connections)
                }
                Button("Not Now", role: .cancel) { }
            } message: {
                Text("Before starting a chat, add your AI service endpoint URL in Connection settings.")
            }
            .toolbar {
                leadingToolbarItems
                principalToolbarItems
                trailingToolbarItems
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(uiColor: .systemGroupedBackground).opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to AI Service…")
                .font(.headline)
            Text("Checking the backend you configured.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unconfiguredView: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack(alignment: .bottomTrailing) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)

                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(Color(uiColor: .systemGroupedBackground)))
                    .accessibilityHidden(true)
            }

            Text("No AI Service Configured")
                .font(.title2.bold())

            Text("Add a Companion or another OpenAI-compatible backend to start chatting.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button("Set Up Connection") {
                path.append(SettingsPath.connections)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Main Content
    private var mainView: some View {
        ZStack(alignment: .leading) {
            LeftSidebarView(
                isPresented: $showLeftSidebar,
                showSettingsSheet: $showSheet
            )
            .environmentObject(chatManager)
            .frame(width: sidebarWidth)
            .allowsHitTesting(showLeftSidebar)
            .zIndex(showLeftSidebar ? 2 : -1)
            
            mainContentAndInput
                .frame(width: UIScreen.main.bounds.width)
                .background(Color(UIColor.systemGroupedBackground))
                .offset(x: showLeftSidebar ? sidebarWidth : 0)
                .disabled(showLeftSidebar)
                .shadow(color: showLeftSidebar ? Color.black.opacity(0.2) : Color.clear, radius: 10, x: -5, y: 0)
                .zIndex(0)
                
            Color.black.opacity(showLeftSidebar ? 0.001 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .allowsHitTesting(showLeftSidebar)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showLeftSidebar = false
                    }
                }
                .zIndex(1)
        }
        .animation(.easeInOut(duration: 0.25), value: showLeftSidebar)
    }
    
    private var unreachableView: some View {
        VStack(alignment: .center, spacing: 20) {
            if chatManager.isLoading {
                ProgressView()
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.red)
                Text("AI Service Unreachable")
                    .font(.headline)
                    .foregroundColor(.red)
                    .padding(.bottom)
                
                Button("Check connection settings") {
                    path.append(SettingsPath.connections)
                }
            }
        }
    }
    
    // MARK: - Content Area
    var mainContentAndInput: some View {
        contentView
        .contentShape(Rectangle())
        .onTapGesture { handleMainContentTap() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if chatManager.activeConversation != nil {
                chatInputBar
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if chatManager.activeConversation == nil && !chatManager.isLoading {
            noConversationView
        } else if currentMessages.isEmpty && !(chatManager.activeConversation?.messages?.contains(where: {$0.isStreaming}) ?? false) {
            welcomeMessage
        } else {
            messagesScrollView
        }
    }
    
    private var noConversationView: some View {
        VStack {
            Text("No Conversation Selected")
                .font(.title)
                .foregroundColor(.gray)
            Text("Create a new chat or select one from the sidebar.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding()
            Button {
                startNewConversation()
                showLeftSidebar = false
            } label: {
                Label("Start New Chat", systemImage: "plus.message.fill")
                    .padding()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var messagesScrollView: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView {
                LazyVStack {
                    ForEach(currentMessages, id: \.id) { message in
                        MessageView(
                            message: message,
                            isShowingActions: selectedMessageID == message.id,
                            onToggleActions: {
                                NotificationCenter.default.post(name: .clearMessageTextSelection, object: nil)
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedMessageID = selectedMessageID == message.id ? nil : message.id
                                }
                            },
                            onRetry: { retryMessage(message) }
                        )
                            .padding()
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("BOTTOM_ANCHOR")
                }
                .onChange(of: currentMessages.count) {
                    scrollToLastMessage(recheckAfterLayout: true)
                }
                .onChange(of: chatManager.currentStreamingMessageContent) {
                    if currentMessages.last?.isStreaming == true {
                        scrollToLastMessage()
                    }
                }
                .onAppear {
                    self.scrollProxy = scrollViewProxy
                    scrollToLastMessage(recheckAfterLayout: true)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
    
    private var chatInputBar: some View {
        ChatInputBar(
            text: $messageText,
            onSend: { sendMessage(typedText: $0) },
            onFocusChanged: { isFocused in
                if isFocused {
                    scrollToLastMessage(recheckAfterLayout: true)
                }
            },
            isReplying: chatManager.isReplying
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                NotificationCenter.default.post(name: .clearMessageTextSelection, object: nil)
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedMessageID = nil
                }
            }
        )
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: HeightPreferenceKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self) { newHeight in
            if self.chatInputBarHeight != newHeight {
                self.chatInputBarHeight = newHeight
                scrollToLastMessage()
            }
        }
    }
    
    @ViewBuilder
    private var welcomeMessage: some View {
        VStack(alignment: .center, spacing: 14) {
            Spacer()
            let greeting = getGreeting()
            Text(greeting)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)

            Text("What's on your mind?")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Toolbar Items
    @ToolbarContentBuilder
    private var leadingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showLeftSidebar.toggle()
                }
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18))
                    .frame(width: 22, height: 22, alignment: .center)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var principalToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if chatManager.isLoading && hasConfiguredServiceURL {
                Text("Connecting…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if chatManager.reachable {
                conversationTitleToolbarItem
            } else if !hasConfiguredServiceURL {
                Text("Companion Connect")
                    .font(.headline.bold())
            } else {
                unreachableToolbarItem
            }
        }
    }
    
    private var conversationTitleToolbarItem: some View {
        Text(activeConversationTitle)
            .font(.headline.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: 240)
            .foregroundColor(.primary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .padding(.bottom, 6)
            .accessibilityLabel("Chat title: \(activeConversationTitle)")
    }
    
    private var unreachableToolbarItem: some View {
        HStack(spacing: 2) {
            Text("AI Service Unreachable").font(.headline).foregroundColor(.red)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .onTapGesture {
            path.append(SettingsPath.connections)
        }
    }
    
    @ToolbarContentBuilder
    private var trailingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                startNewConversation()
            }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18))
                    .frame(width: 22, height: 22, alignment: .center)
            }
        }
    }
    
    // MARK: - Helper Methods
    private func startNewConversation() {
        guard AIProviderConfiguration.hasConfiguredServiceURL else {
            showConnectionRequiredAlert = true
            return
        }
        chatManager.createNewConversation()
    }

    private func handleMainContentTap() {
        NotificationCenter.default.post(name: .clearMessageTextSelection, object: nil)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        if showLeftSidebar {
            showLeftSidebar = false
        }
    }
    
    private func scrollToLastMessage(recheckAfterLayout: Bool = false) {
        DispatchQueue.main.async {
            withAnimation {
                scrollProxy?.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
            }

            guard recheckAfterLayout else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation {
                    scrollProxy?.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                }
            }
        }
    }
    
    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default: return "Good Evening"
        }
    }
    
    private func sendMessage(typedText: String) {
        guard chatManager.activeConversation != nil else {
            print("Cannot send message: No active conversation.")
            chatManager.errorMessage = "Please start or select a conversation."
            return
        }
        
        var attachmentData: (fileName: String, fileContent: String)?
        if let fileName = attachmentManager.selectedFileName,
           let fileContent = attachmentManager.importedFileContent {
            attachmentData = (fileName: fileName, fileContent: fileContent)
        }
        
        Task {
            do {
                if attachmentData != nil {
                    await MainActor.run {
                        attachmentManager.clearAttachment()
                    }
                }
                
                try await chatManager.sendMessage(
                    typedText: typedText,
                    attachmentDetails: attachmentData
                )
            } catch let error as ChatManagerError {
                print("\(error.localizedDescription)")
            } catch {
                print("\(error.localizedDescription)")
                await MainActor.run {
                    chatManager.errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
                }
            }
        }
    }

    private func retryMessage(_ message: ChatMessage) {
        guard !chatManager.isReplying else { return }

        if message.role == .user {
            sendMessage(typedText: message.content)
            return
        }

        Task {
            do {
                try await chatManager.regenerateResponse(message)
            } catch {
                await MainActor.run {
                    chatManager.errorMessage = "Could not regenerate the response: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Sidebar View
struct LeftSidebarView: View {
    @Binding var isPresented: Bool
    @Binding var showSettingsSheet: Bool
    @EnvironmentObject var chatManager: ChatManager
    
    @State private var showingDeleteConfirmation = false
    @State private var conversationToDelete: Conversation?
    @State private var showingRenamePrompt = false
    @State private var conversationToRename: Conversation?
    @State private var renamedTitle = ""
    
    @State private var searchText = ""
    
    var filteredConversations: [Conversation] {
        let sortedConversations = chatManager.conversations.sorted(by: { $0.lastActivityDate > $1.lastActivityDate })
        
        if searchText.isEmpty {
            return sortedConversations
        } else {
            return sortedConversations.filter { conversation in
                let titleMatch = conversation.title.localizedCaseInsensitiveContains(searchText)
                let messageMatch = conversation.messages?.contains { message in
                    message.content.localizedCaseInsensitiveContains(searchText)
                }
                return titleMatch || (messageMatch != nil)
            }
        }
    }
    
    var conversationSections: [DisplayableConversationSection] {
        let now = Date()
        let calendar = Calendar.current
        
        let groupedDictionary = Dictionary(grouping: filteredConversations) { conversation in
            categorise(date: conversation.lastActivityDate, calendar: calendar, now: now)
        }
        
        return groupedDictionary.map { (dateGroup, conversations) in
            DisplayableConversationSection(id: dateGroup, conversations: conversations)
        }
        .sorted { $0.id.displayOrder < $1.id.displayOrder }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            conversationsList
            Spacer()
            footerSection
        }
        .background(Color(UIColor.secondarySystemBackground))
    }
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search Conversations", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemGray5))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var conversationsList: some View {
        List {
            ForEach(conversationSections) { section in
                Section(header: Text(section.title).font(.caption.weight(.semibold))) {
                    ForEach(section.conversations) { conversation in
                        ConversationRowView(
                            conversation: conversation,
                            isActive: chatManager.activeConversation?.id == conversation.id,
                            onSelect: {
                                chatManager.selectConversation(conversation)
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isPresented = false
                                }
                            }
                        )
                        .contextMenu {
                            Button {
                                conversationToRename = conversation
                                renamedTitle = conversation.title
                                showingRenamePrompt = true
                            } label: {
                                Label("Rename Chat", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                conversationToDelete = conversation
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete Chat", systemImage: "trash.fill")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                conversationToDelete = conversation
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .padding(.horizontal, -10)
            }
        }
        .listStyle(PlainListStyle())
        .environment(\.defaultMinListRowHeight, 30)
        .alert("Delete Conversation?", isPresented: $showingDeleteConfirmation, presenting: conversationToDelete) { convToDelete in
            Button("Delete", role: .destructive) {
                chatManager.deleteConversation(convToDelete)
                conversationToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                conversationToDelete = nil
            }
        } message: { convToDelete in
            Text("Are you sure you want to delete the chat titled \"\(convToDelete.title)\"? This cannot be undone.")
        }
        .alert("Rename Conversation", isPresented: $showingRenamePrompt, presenting: conversationToRename) { conversation in
            TextField("Conversation title", text: $renamedTitle)
            Button("Rename") {
                chatManager.renameConversation(conversation, to: renamedTitle)
                conversationToRename = nil
            }
            Button("Cancel", role: .cancel) {
                conversationToRename = nil
            }
        } message: { _ in
            Text("Enter a new title. Automatic title updates will stop for this conversation.")
        }
    }
    
    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: {
                isPresented = false
                showSettingsSheet = true
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
        }
    }
    
    private func categorise(date: Date, calendar: Calendar = .current, now: Date = Date()) -> DateSectionGroup {
        let startOfToday = calendar.startOfDay(for: now)
        
        if calendar.isDate(date, inSameDayAs: startOfToday) {
            return .today
        }
        
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        if calendar.isDate(date, inSameDayAs: startOfYesterday) {
            return .yesterday
        }
        
        let sevenDaysAgoBoundary = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        if date < startOfYesterday && date >= sevenDaysAgoBoundary {
            return .previous7Days
        }
        
        let thirtyDaysAgoBoundary = calendar.date(byAdding: .day, value: -30, to: startOfToday)!
        if date < sevenDaysAgoBoundary && date >= thirtyDaysAgoBoundary {
            return .previous30Days
        }
        
        return .older
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(conversation.title)
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(isActive ? .white : .primary)
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive ? Color.accentColor : Color.clear
            )
            .contentShape(Rectangle())
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Message View
struct MessageView: View {
    let message: ChatMessage
    let isShowingActions: Bool
    let onToggleActions: () -> Void
    let onRetry: () -> Void
    @State private var isThinkingExpanded: Bool = false
    @AppStorage("showTokenPerSeconds") private var showTokenPerSeconds: Bool = true
    @AppStorage("chatFontSize") private var chatFontSize: Int = 15

    private var isUserMessage: Bool {
        message.role == .user
    }
    
    var body: some View {
        let currentDisplayPhase = MessageDisplayPhase(rawValue: message.displayPhase) ?? .pending
        
        let showThinkingIndicatorActive = currentDisplayPhase == .thinking && message.isStreaming
        
        let assistantAnswerText = (currentDisplayPhase == .answering || currentDisplayPhase == .complete) ? message.content : ""
        
        HStack {
            if isUserMessage { Spacer(minLength: 20) }

            VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                if isUserMessage, let fileNames = message.attachmentFileNames, !fileNames.isEmpty {
                    ForEach(fileNames, id: \.self) { fileName in
                        attachmentView(fileName: fileName)
                    }
                }
                
                if isUserMessage {
                    let userDisplayedText = message.content.isEmpty && message.isStreaming ? "..." : message.content
                    if !userDisplayedText.isEmpty {
                        SelectableTextView(
                            text: userDisplayedText,
                            fontSize: CGFloat(chatFontSize),
                            textColor: .white,
                            selectionColor: .white
                        )
                    }
                } else {
                    if showThinkingIndicatorActive {
                        TypingIndicatorView()
                    }
                    
                    if currentDisplayPhase == .complete, let thinkingText = message.thinkingSteps, !thinkingText.isEmpty {
                        DisclosureGroup(isExpanded: $isThinkingExpanded) {
                            Markdown(thinkingText)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .padding(.top, 4)
                        } label: {
                            Text("Show Thinking Process")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, assistantAnswerText.isEmpty && !showThinkingIndicatorActive ? 0 : 8)
                    }
                    if !assistantAnswerText.isEmpty {
                        SelectableTextView(
                            text: assistantAnswerText,
                            fontSize: CGFloat(chatFontSize),
                            textColor: .black,
                            selectionColor: .systemBlue,
                            rendersMarkdown: true
                        )
                            .id("answer_\(message.id)")
                    } else if message.isStreaming && !showThinkingIndicatorActive && assistantAnswerText.isEmpty && currentDisplayPhase != .complete {
                        TypingIndicatorView()
                    }
                }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundColor(isUserMessage ? Color.white : Color.black)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            isUserMessage
                                ? Color(red: 0.27, green: 0.48, blue: 0.68)
                                : Color(uiColor: .systemGray5)
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .highPriorityGesture(
                    TapGesture().onEnded {
                        guard !message.isStreaming else { return }
                        onToggleActions()
                    }
                )

                if !isUserMessage, currentDisplayPhase == .complete, let tps = message.tokensPerSecond, showTokenPerSeconds {
                    Text(String(format: "%@%.0f t/s", message.tokensPerSecondIsEstimated ? "≈" : "", tps))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }

                if isShowingActions && !message.isStreaming {
                    messageActions
                        .transition(.scale(scale: 0.9, anchor: isUserMessage ? .topTrailing : .topLeading).combined(with: .opacity))
                }
            }
            
            if !isUserMessage { Spacer(minLength: 20) }
        }
        .frame(maxWidth: .infinity, alignment: isUserMessage ? .trailing : .leading)
    }

    private var messageActions: some View {
        HStack(spacing: 18) {
            if !message.content.isEmpty {
                Button {
                    onToggleActions()
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(isUserMessage ? "Resend message" : "Regenerate response")
            }

            Button {
                UIPasteboard.general.string = message.content
                HapticManager.notificationOccurred(.success)
                onToggleActions()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel("Copy message")
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
    }
    
    private func attachmentView(fileName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
                .font(.callout)
                .foregroundColor(isUserMessage ? Color.white.opacity(0.8) : Color.secondary)
            Text(fileName)
                .font(.caption.weight(.medium))
                .foregroundColor(isUserMessage ? Color.white : Color.black)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isUserMessage
                ? Color.white.opacity(0.18)
                : Color(uiColor: .systemGray4).opacity(0.65)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TypingIndicatorView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: scenePhase != .active
            )
        ) { context in
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    let angle = ((elapsed - Double(index) * 0.15) / 0.9) * 2 * Double.pi
                    let progress = (sin(angle) + 1) / 2

                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(0.72 + 0.28 * progress)
                        .offset(y: 2 - 5 * progress)
                        .opacity(0.45 + 0.55 * progress)
                }
            }
        }
        .frame(height: 18)
    }
}

// MARK: - Chat Input Bar
struct ChatInputBar: View {
    @EnvironmentObject var speechManager: SpeechToTextManager
    @EnvironmentObject var attachmentManager: AttachmentManager
    @EnvironmentObject var chatManager: ChatManager
    
    @Binding var text: String
    let onSend: (String) -> Void
    let onFocusChanged: (Bool) -> Void
    var isReplying: Bool
    @State private var isSubmitting = false
    @FocusState private var isTextFieldFocused: Bool

    @AppStorage("chatFontSize") private var chatFontSize: Int = 15
    
    private var cantSend: Bool {
        (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
         attachmentManager.importedFileContent == nil) || isReplying
    }
    
    var body: some View {
        VStack(spacing: 0) {
            attachmentSection
            textInputSection
        }
        .background(backgroundView)
        .overlay {
            borderOverlay
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .onChange(of: speechManager.transcribedText) {
            guard !isSubmitting, !chatManager.isReplying else { return }
            text = speechManager.transcribedText
        }
        .onChange(of: chatManager.isReplying) { _, replying in
            if !replying {
                isSubmitting = false
            }
        }
        .fileImporter(
            isPresented: $attachmentManager.showFileImporter,
            allowedContentTypes: attachmentManager.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            attachmentManager.handleFileImport(result: result)
        }
    }
    
    @ViewBuilder
    private var attachmentSection: some View {
        if let fileName = attachmentManager.selectedFileName {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.gray)
                Text(fileName)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button {
                    attachmentManager.clearAttachment()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
    
    private var textInputSection: some View {
        HStack(alignment: .center, spacing: 6){
            attachmentMenu
            TextField("Ask anything", text: $text, axis: .vertical)
                .font(.system(size: CGFloat(chatFontSize), weight: .regular, design: .default))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.clear)
                .scrollContentBackground(.hidden)
                .focused($isTextFieldFocused)
                .onChange(of: isTextFieldFocused) { _, isFocused in
                    onFocusChanged(isFocused)
                }
                .onSubmit { if !isReplying { prepareAndSendMessage() } }
            if chatManager.isReplying {
                stopButton
            } else if text.isEmpty {
                microphoneButton
            } else {
                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private var attachmentMenu: some View {
        Menu {
            Button(action: { attachmentManager.selectFile() }) {
                HStack {
                    Image(systemName: "folder.fill")
                    Text("Files")
                }
            }
            
            Button(action: {}) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Camera")
                }
            }
            .disabled(true)
            
            Button(action: {}) {
                HStack {
                    Image(systemName: "photo.fill")
                    Text("Photo Library")
                }
            }
            .disabled(true)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.accentColor)
        }
    }
    
    private var microphoneButton: some View {
        Button(action: {
            if speechManager.isRecording {
                speechManager.stopRecording()
            } else {
                speechManager.startRecording()
            }
        }) {
            Image(systemName: speechManager.isRecording ? "stop.fill" : "waveform.circle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(speechManager.isRecording ? Color.red : Color.accentColor)
        }
        .disabled(!speechManager.isSpeechRecognitionAvailable)
    }
    
    private var sendButton: some View {
        Button(action: {
            HapticManager.impactOccurred(style: .medium)
            if !cantSend {
                if speechManager.isRecording { speechManager.stopRecording() }
                prepareAndSendMessage()
            }
        }) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(cantSend ? Color(uiColor: .systemGray3) : Color.accentColor)
        }
        .disabled(cantSend)
    }
    
    private var stopButton: some View {
        Button(action: {
            HapticManager.impactOccurred(style: .medium)
            chatManager.stopGeneratingResponse()
        }){
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityLabel("Stop response")
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }
    
    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 1)
    }
    
    private func prepareAndSendMessage() {
        guard !cantSend else { return }
        if speechManager.isRecording { speechManager.stopRecording() }
        let submittedText = text
        isSubmitting = true
        text = ""
        speechManager.transcribedText = ""
        onSend(submittedText)
    }
}

#Preview {
    Main()
        .preferredColorScheme(.dark)
}
