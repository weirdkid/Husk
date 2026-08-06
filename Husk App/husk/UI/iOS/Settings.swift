//
//  Settings.swift
//  husk
//
//  Created by Nathan Ellis on 30/05/2025.
//
import SwiftUI

struct Settings: View {
    
    @AppStorage("isHapticFeedbackOn") private var isHapticFeedbackOn: Bool = true
    @AppStorage("showTokenPerSeconds") private var showTokenPerSeconds: Bool = true
    @AppStorage("chatFontSize") private var chatFontSize: Int = 15
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .center, spacing: 20) {
                List{
                    Section("General"){
                        NavigationLink(destination: ConnectionsView()) {
                            HStack {
                                Image(systemName: "network")
                                    .foregroundColor(Color.primary)
                                Text("Connection")
                                Spacer()
                            }
                        }
                        
                    }
                    Section(
                        header: Text("App"),
                        footer: Text("Conversation history is stored by your Companion service and cached on this device for responsive, offline access.")
                    ){
                        Toggle(isOn: $isHapticFeedbackOn) {
                            HStack {
                                Image(systemName: "iphone.radiowaves.left.and.right")
                                    .foregroundColor(Color.primary)
                                Text("Haptic Feedback")
                            }
                        }.onChange(of: isHapticFeedbackOn){
                            HapticManager.selectionChanged()
                        }
                        
                        Toggle(isOn: $showTokenPerSeconds) {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(Color.primary)
                                Text("Show Tokens Per Second (TPS)")
                            }
                        }
                        
                    }

                    Section(
                        header: Text("Chat Text Size"),
                        footer: Text("Changes apply to your messages and companion responses.")
                    ) {
                        Picker("Chat Text Size", selection: $chatFontSize) {
                            ForEach([13, 15, 17, 19], id: \.self) { size in
                                HStack {
                                    Text(sizeLabel(for: size))
                                    Spacer()
                                    Text("Abc")
                                        .font(.system(size: CGFloat(size)))
                                }
                                .tag(size)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    
                    Section("About"){
                        
                        Button(action: {
                            if let url = URL(string: "mailto:contact@weirdkid.com") {
                                UIApplication.shared.open(url)
                            }
                        }){
                            HStack {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(Color.primary)
                                Text("Help")
                                Spacer()
                                Image(systemName: "arrowshape.turn.up.right.fill")
                                    .foregroundColor(Color.gray)
                            }
                        }
                        Button(action: {
                            if let url = URL(string: "https://github.com/weirdkid/Husk") {
                                UIApplication.shared.open(url)
                            }
                        }){
                            HStack {
                                Image(systemName: "qrcode")
                                    .foregroundColor(Color.primary)
                                Text("Source Code")
                                Spacer()
                                Image(systemName: "arrowshape.turn.up.right.fill")
                                    .foregroundColor(Color.gray)
                            }
                        }
                        
                        Button(action: {
                            if let url = URL(string: "https://github.com/weirdkid/Husk") {
                                UIApplication.shared.open(url)
                            }
                        }){
                            HStack {
                                Image(systemName: "rectangle.3.group.fill")
                                    .foregroundColor(Color.primary)
                                Text("Acknowledgements")
                                Spacer()
                                Image(systemName: "arrowshape.turn.up.right.fill")
                                    .foregroundColor(Color.gray)
                            }
                        }
                    }
            }
            .background(.clear)
            .scrollContentBackground(.hidden)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.footnote)
                    .foregroundColor(Color.gray)
                    .padding(.top, 10)
                
            }
            .navigationTitle("Settings")
            .toolbar{
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.gray)
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
    }
    
    private func sizeLabel(for size: Int) -> String {
        switch size {
        case 13: "Extra Small"
        case 15: "Small"
        case 19: "Large"
        default: "Medium"
        }
    }
}

struct ConnectionsView: View {
    
    
    @EnvironmentObject var chatManager: ChatManager
    
    @AppStorage(AIProviderConfiguration.serviceURLPreferenceKey)
    var serviceURL: String = ""
    @AppStorage(AIProviderConfiguration.responseTimeoutPreferenceKey)
    private var responseTimeoutSeconds: Int = Int(AIProviderConfiguration.defaultResponseTimeout)
    @State private var apiKey = AIProviderConfiguration.loadAPIKey()
    @State private var lastAppliedServiceURL: String?
    @State private var lastAppliedAPIKey: String?
    
    var body: some View {
        List {
            Section(
                header: Text("Companion Service"),
                footer: Text("Enter the complete OpenAI-compatible base URL, including any port and path.\nExample: http://localhost:8080/v1")
            ) {
                TextField("", text: $serviceURL)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit {
                        applyConnectionSettings()
                    }
            }

            Section(
                header: Text("Authentication"),
                footer: Text("The API key is stored securely in this device's Keychain and sent as a bearer token to the Companion service.")
            ) {
                SecureField("API Key", text: $apiKey)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
                    .submitLabel(.done)
                    .onSubmit {
                        applyConnectionSettings()
                    }
                    .privacySensitive()
            }

            Section(
                header: Text("Response Timeout"),
                footer: Text("How long Companion Connect waits when no new response data arrives. Streaming responses can continue longer as long as data keeps arriving.")
            ) {
                Picker("Inactivity Timeout", selection: $responseTimeoutSeconds) {
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("30 minutes").tag(1_800)
                }
            }
        }
        .navigationTitle("Connection")
        .scrollDismissesKeyboard(.interactively)
        .onDisappear {
            applyConnectionSettings()
        }
        .onChange(of: responseTimeoutSeconds) {
            chatManager.updateConnectionSettings()
        }
    }

    private func applyConnectionSettings() {
        serviceURL = serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard serviceURL != lastAppliedServiceURL || apiKey != lastAppliedAPIKey else {
            return
        }
        lastAppliedServiceURL = serviceURL
        lastAppliedAPIKey = apiKey
        AIProviderConfiguration.saveAPIKey(apiKey)
        chatManager.updateConnectionSettings()
    }

}
