//
//  Settings.swift
//  husk
//
//  Created by Nathan Ellis on 30/05/2025.
//
import SwiftUI
import CloudKit

struct Settings: View {
    
    @AppStorage("isHapticFeedbackOn") private var isHapticFeedbackOn: Bool = true
    @AppStorage("showTokenPerSeconds") private var showTokenPerSeconds: Bool = true
    @AppStorage("shouldSyncWithiCloud") private var userSettingForiCloudSync: Bool = false
    @AppStorage("chatFontSize") private var chatFontSize: Int = 15
    
    @State private var showiCloudStatusAlert: Bool = false
    @State private var isProgrammaticallyUpdatingToggle: Bool = false

    
    @State private var currentAlertTitle: String = ""
    @State private var currentAlertMessage: String = ""
    
    @Environment(\.dismiss) private var dismiss
    
    private var iCloudSectionFooterText: String {
        if userSettingForiCloudSync {
            return "Your conversations will attempt to sync with iCloud on the next app launch. To stop syncing, toggle this off and restart the app."
        } else {
            return "Enable iCloud Sync to back up your conversations and access them across your devices. This requires an app restart to take effect."
        }
    }

    private var iCloudAlertTitle: String {
        if userSettingForiCloudSync {
            return "iCloud Sync Will Be Enabled"
        } else {
            return "iCloud Sync Will Be Disabled"
        }
    }

    private var iCloudAlertMessage: String {
        let restartMessage = "Please restart Husk for this change to take full effect."
        if userSettingForiCloudSync {
            return "On the next app launch, your conversations will begin syncing with your iCloud account. \(restartMessage)"
        } else {
            return "On the next app launch, conversations will no longer sync with iCloud and will be stored only on this device. \(restartMessage)"
        }
    }
    
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
                        footer: Text(iCloudSectionFooterText)
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
                        
                        Toggle(isOn: $userSettingForiCloudSync) {
                            HStack {
                                Image(systemName: userSettingForiCloudSync ? "icloud.fill" : "icloud.slash.fill")
                                    .foregroundColor(userSettingForiCloudSync ? .blue : .gray)
                                Text("iCloud Sync")
                            }
                        }
                        .onChange(of: userSettingForiCloudSync) { oldValue, newValue in
                            HapticManager.selectionChanged()
                            if isProgrammaticallyUpdatingToggle {
                                isProgrammaticallyUpdatingToggle = false
                                return
                            }
                            
                            
                            if newValue == true {
                                checkiCloudAccountStatus { status in
                                    DispatchQueue.main.async {
                                        var shouldRevertToggle = false
                                        switch status {
                                        case .available:
                                            self.currentAlertTitle = "iCloud Sync Will Be Enabled"
                                            self.currentAlertMessage = "On the next app launch, your conversations will begin syncing with your iCloud account. Please restart Husk for this change to take full effect."
                                        case .noAccount:
                                            self.currentAlertTitle = "iCloud Account Needed"
                                            self.currentAlertMessage = "To enable iCloud Sync, please sign in to your iCloud account in the device Settings, then enable this setting again. An app restart will be required."
                                            shouldRevertToggle = true
                                        case .restricted:
                                            self.currentAlertTitle = "iCloud Restricted"
                                            self.currentAlertMessage = "Your iCloud account is restricted (e.g., parental controls). iCloud Sync cannot be enabled. Please check your device Settings."
                                            shouldRevertToggle = true
                                        case .couldNotDetermine:
                                            self.currentAlertTitle = "iCloud Status Unknown"
                                            self.currentAlertMessage = "Could not determine iCloud account status. Please check your internet connection and iCloud settings, then try again. An app restart will be required if you proceed."
                                            shouldRevertToggle = true
                                        case .temporarilyUnavailable:
                                            self.currentAlertTitle = "iCloud Temporarily Unavailable"
                                            self.currentAlertMessage = "iCloud is temporarily unavailable. Please try again later. An app restart will be required if you proceed."
                                            shouldRevertToggle = true
                                        @unknown default:
                                            self.currentAlertTitle = "iCloud Error"
                                            self.currentAlertMessage = "An unknown iCloud error occurred. Please check your iCloud settings. An app restart will be required if you proceed."
                                            shouldRevertToggle = true
                                        }
                                        if shouldRevertToggle {
                                            self.isProgrammaticallyUpdatingToggle = true
                                            self.userSettingForiCloudSync = false
                                        }
                                        self.showiCloudStatusAlert = true
                                    }
                                }
                            } else {
                                self.currentAlertTitle = "iCloud Sync Will Be Disabled"
                                self.currentAlertMessage = "On the next app launch, conversations will no longer sync with iCloud and will be stored only on this device. Please restart Husk for this change to take full effect."
                                self.showiCloudStatusAlert = true
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
            .alert(currentAlertTitle, isPresented: $showiCloudStatusAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(currentAlertMessage)
            }
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
    
    private func checkiCloudAccountStatus(completion: @escaping (CKAccountStatus) -> Void) {
        CKContainer.default().accountStatus { status, error in
            if let error = error {
                print("Error checking iCloud account status: \(error.localizedDescription)")
                completion(.couldNotDetermine)
                return
            }
            completion(status)
        }
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
                footer: Text("How long Husk waits when no new response data arrives. Streaming responses can continue longer as long as data keeps arriving.")
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
