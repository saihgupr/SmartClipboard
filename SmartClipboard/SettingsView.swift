import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            AISettingsView()
                .tabItem {
                    Label("AI & Search", systemImage: "sparkles")
                }
            
            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 550, height: 450)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("historyRetentionDays") private var historyRetentionDays: Int = 180

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 20) {
                // Login Item
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Launch SmartClipboard at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            updateLoginItem(enabled: newValue)
                        }
                    Text("Automatically start the app when you turn on your Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                Divider()

                // History Retention
                VStack(alignment: .leading, spacing: 6) {
                    Picker("History Retention:", selection: $historyRetentionDays) {
                        Text("7 Days").tag(7)
                        Text("30 Days").tag(30)
                        Text("90 Days").tag(90)
                        Text("180 Days (6 mo)").tag(180)
                        Text("1 Year").tag(365)
                        Text("Forever").tag(0)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 250)
                    
                    Text("Controls how long clipboard items are kept before automatic deletion.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
    }
    
    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
}

struct AISettingsView: View {
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-1.5-flash"
    @AppStorage("semanticSearchDepth") private var semanticSearchDepth: Int = 200
    
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false
    
    private let geminiService = GeminiService()

    var body: some View {
        Form {
            Section {
                SecureField("API Key:", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Link("Get API Key", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Button("Test Connection") {
                        fetchModels()
                    }
                    .disabled(isLoadingModels || apiKey.isEmpty)
                    .help(apiKey.isEmpty ? "API key required to test connection" : "Test API connection")
                }
                
                if showSuccessMessage {
                    Text("Connection successful!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } header: {
                Text("Gemini API")
            } footer: {
                Text("API key is required for AI features.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Section {
                if availableModels.isEmpty {
                    if isLoadingModels {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(height: 20)
                    } else {
                        Button("Fetch Available Models") {
                            fetchModels()
                        }
                        .disabled(apiKey.isEmpty)
                        .help(apiKey.isEmpty ? "API key required to fetch models" : "Fetch available models from Gemini")
                    }
                } else {
                    HStack {
                        Picker("Model Version:", selection: $selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        Button(action: fetchModels) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh Models")
                        .accessibilityLabel("Refresh Models")
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            } header: {
                Text("Model Selection")
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Section {
                Slider(value: Binding(get: {
                    Double(semanticSearchDepth)
                }, set: { newValue in
                    semanticSearchDepth = Int(newValue)
                }), in: 200...2000, step: 50) {
                    Text("Semantic Search Depth:")
                }
                
                Text("\(semanticSearchDepth) items. Higher values search further back in history but use more AI tokens (max 2000).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Search Settings")
            }
        }
        .padding(20)
        .onAppear {
            if availableModels.isEmpty && !apiKey.isEmpty {
                fetchModels()
            }
        }
    }
    
    func fetchModels() {
        isLoadingModels = true
        errorMessage = nil
        showSuccessMessage = false
        
        Task {
            do {
                let models = try await geminiService.fetchModels(apiKey: apiKey)
                await MainActor.run {
                    self.availableModels = models
                    withAnimation {
                        self.showSuccessMessage = true
                    }
                    
                    if !models.contains(selectedModel) && !models.isEmpty {
                        self.selectedModel = models.contains("gemini-1.5-flash") ? "gemini-1.5-flash" : (models.first ?? "")
                    }
                    self.isLoadingModels = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { self.showSuccessMessage = false }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Connection error: Check your API key or internet."
                    self.isLoadingModels = false
                }
            }
        }
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                ShortcutRecorderView()
                Text("This shortcut toggles the clipboard window from anywhere.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Global Hotkey")
            }
            
            Divider()
                .padding(.vertical, 8)
                
            Section {
                AppSpecificSettingsView()
            } header: {
                Text("App Specific Settings")
            }
        }
        .padding(20)
    }
}
