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
    @AppStorage("ollamaURL") var serviceHost: String = ""
    @AppStorage("ollamaPort") var servicePort: String = "11434"

    @State private var isTestingConnection: Bool = false
    @State private var testConnectionMessage: String? = nil
    @State private var connectionTestSuccess: Bool = false
    
    private var constructedURL: URL? {
        var hostComponent = serviceHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let portComponent = servicePort.trimmingCharacters(in: .whitespacesAndNewlines)

        if hostComponent.isEmpty || portComponent.isEmpty {
            testConnectionMessage = "Host and Port cannot be empty."
            return nil
        }

        if !hostComponent.lowercased().hasPrefix("http://") && !hostComponent.lowercased().hasPrefix("https://") {
            hostComponent = "http://" + hostComponent
        }
        
        guard var urlComponents = URLComponents(string: hostComponent) else {
            testConnectionMessage = "Invalid server address format."
            return nil
        }
        
        if let portNumber = Int(portComponent), portNumber > 0 && portNumber <= 65535 {
            urlComponents.port = portNumber
        } else {
            testConnectionMessage = "Invalid port number. Must be between 1-65535."
            return nil
        }
        
        guard urlComponents.host != nil, !urlComponents.host!.isEmpty else {
            testConnectionMessage = "Server address missing host."
            return nil
        }
        
        return urlComponents.url
    }
    
    private var buttonDisabled: Bool {
        serviceHost.isEmpty || servicePort.isEmpty
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
                    TextField("Address (e.g., http://localhost)", text: $serviceHost)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("Port (e.g., 11434)", text: $servicePort)
                        .keyboardType(.numberPad)
                }
            }
            .scrollDisabled(true)
            .frame(maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            Text("Use port 11434 for Ollama, or the port exposed by your Companion service. iOS may ask for permission to connect to local network devices.")
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
        .onChange(of: serviceHost) {resetTestStatusOnInputChange()}
        .onChange(of: servicePort) {resetTestStatusOnInputChange()}
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
                 self.testConnectionMessage = "Invalid URL or Port. Please check your input."
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
                    let originalHostHadNoScheme = !self.serviceHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http")
                    let finalHostStartsWithHttp = url.absoluteString.lowercased().hasPrefix("http://")
                    
                    if originalHostHadNoScheme && finalHostStartsWithHttp {
                        var hostToStore = url.host ?? self.serviceHost
                        if !hostToStore.lowercased().hasPrefix("http://"){
                             hostToStore = "http://" + hostToStore
                        }
                        if self.serviceHost != hostToStore {
                             self.serviceHost = hostToStore
                        }
                    }

                    self.testConnectionMessage = "Successfully connected to the AI service at \(url.absoluteString)!"
                    self.connectionTestSuccess = true
                } else {
                    self.testConnectionMessage = "Failed to connect. Check the address and port, and make sure the service is accessible from this device."
                    self.connectionTestSuccess = false
                }
            }
        }
    }
}
