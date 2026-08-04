//
//  Onboarding.swift
//  husk
//
//  Created by Nathan Ellis on 31/05/2025.
//
import SwiftUI

struct Onboarding: View {
    
    
    @State private var glowRadius: CGFloat = 5
    @State private var navigationPath = NavigationPath()
    
    var body: some View{
        NavigationStack(path: $navigationPath){
            VStack(alignment: .center, spacing: 20) {
                Spacer()
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                Text("Welcome to\nHusk")
                    .font(.largeTitle)
                    .bold()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .purple.opacity(0.7), radius: glowRadius, x: 0, y: 0)
                    .shadow(color: .indigo.opacity(0.5), radius: glowRadius * 1.5, x: 0, y: 0)
                    .shadow(color: .purple.opacity(0.3), radius: glowRadius * 2, x: 0, y: 0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: glowRadius)
                    .onAppear {
                        glowRadius = 20
                    }
                
                Spacer()
                
                Button(action: {
                    navigationPath.append(OnboardingPath.aiServiceConnection)
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 50)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.purple)
                        )
                }
                
                Spacer()
            }
            .navigationDestination(for: OnboardingPath.self) { path in
                switch path {
                case .aiServiceConnection:
                    AIServiceConnection(path: $navigationPath)
                }
            }
        }
    }
}

struct AIServiceConnection: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var chatManager: ChatManager

    @AppStorage("onboarded") var onboarded: Bool = false
    @AppStorage(AIProviderConfiguration.serviceURLPreferenceKey) var serviceURL: String = ""

    @State private var isTestingConnection: Bool = false
    @State private var testConnectionMessage: String? = nil
    @State private var connectionTestSuccess: Bool = false
    
    private var constructedURL: URL? {
        AIProviderConfiguration.makeBaseURL(from: serviceURL)
    }
    
    private var buttonDisabled: Bool {
        serviceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .center, spacing: 15) {
            Image(systemName: "network")
                .font(.system(size: 50))
                .foregroundColor(.accentColor)
                .padding(.top)
            
            Text("Connect Your AI Service")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Enter the address of your Companion service or any server with an OpenAI-compatible API, including Ollama.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Form {
                Section(header: Text("Server Details").font(.callout)) {
                    TextField("http://localhost:8080/v1", text: $serviceURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .scrollDisabled(true)
            .frame(maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            Text("Enter the complete OpenAI-compatible base URL, including its scheme, optional port, and path. iOS may ask for permission to connect to local network devices.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            if let message = testConnectionMessage {
                HStack {
                    Image(systemName: connectionTestSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    Text(message)
                }
                .font(.footnote)
                .foregroundColor(connectionTestSuccess ? .green : .red)
                .multilineTextAlignment(.leading)
                .padding(.horizontal)
                .padding(.vertical, 5)
            }
            
            Button(action: testAIConnection) {
                Group {
                    if isTestingConnection {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Check Connection")
                            .font(.headline)
                            .foregroundStyle(buttonDisabled ? .white.opacity(0.4) : .white)
                    }
                }
                .frame(minWidth: 200)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(buttonDisabled ? .purple.opacity(0.4) : .purple)
                )
            }
            .disabled(buttonDisabled)
            .padding([.horizontal, .bottom])
        }
        .padding(.top)
        .navigationBarBackButtonHidden()
        .onChange(of: serviceURL) {resetTestStatusOnInputChange()}
        .onChange(of: connectionTestSuccess){
            onboarded = true
        }
    }

    func resetTestStatusOnInputChange() {
        if connectionTestSuccess || testConnectionMessage != nil {
            connectionTestSuccess = false
            testConnectionMessage = "Settings changed. Please test the connection again."
            isTestingConnection = false
        }
    }

    func testAIConnection() {
        guard let url = constructedURL else {
            if self.testConnectionMessage == nil {
                 self.testConnectionMessage = "Enter a valid HTTP or HTTPS service URL."
            }
            self.connectionTestSuccess = false
            self.isTestingConnection = false
            return
        }

        self.isTestingConnection = true
        self.testConnectionMessage = "Attempting to connect..."
        self.connectionTestSuccess = false

        Task {
            let reachable = await chatManager.testConnection(
                configuration: .init(baseURL: url)
            )
            await MainActor.run {
                self.isTestingConnection = false
                if reachable {
                    self.serviceURL = url.absoluteString
                    self.testConnectionMessage = "Successfully connected to the AI service at \(url.absoluteString)!"
                    self.connectionTestSuccess = true
                } else {
                    self.testConnectionMessage = "Failed to connect. Check the URL and make sure the service is accessible from this device."
                    self.connectionTestSuccess = false
                }
            }
        }
    }
}
