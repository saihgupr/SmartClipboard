import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-1.5-flash"
    @AppStorage("semanticSearchDepth") private var semanticSearchDepth: Int = 200
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("historyRetentionDays") private var historyRetentionDays: Int = 180
    
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false
    @State private var showClearConfirmation = false
    
    var onDismiss: () -> Void
    
    private let geminiService = GeminiService()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { onDismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("AI Settings")
                    .font(.headline)
                
                Spacer()
                
                // Invisible spacer to balance the back button
                Image(systemName: "chevron.left")
                    .opacity(0)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Quick Options Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Options")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Toggle("Launch SmartClipboard at Login", isOn: $launchAtLogin)
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { oldValue, newValue in
                                updateLoginItem(enabled: newValue)
                            }
                        
                        Button(action: { NSApplication.shared.terminate(nil) }) {
                            HStack {
                                Image(systemName: "power")
                                Text("Quit SmartClipboard")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Text("These settings apply immediately to your app experience.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // API Key Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API Key")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                                HStack(spacing: 4) {
                                    Text("Get Key")
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        HStack {
                            SecureField("Enter your Gemini API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(action: { fetchModels() }) {
                                if isLoadingModels {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 40, height: 20)
                                } else {
                                    Text("Test")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 40)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isLoadingModels)
                        }
                        
                        if showSuccessMessage {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Connection successful!")
                            }
                            .font(.caption)
                            .foregroundColor(.green)
                            .transition(.opacity)
                        }
                        
                        Text("API key is required for AI features.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Model Selection Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Model Version")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if isLoadingModels {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 16, height: 16)
                            } else {
                                Button(action: fetchModels) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        if availableModels.isEmpty {
                            if !isLoadingModels {
                                Button("Fetch Available Models") {
                                    fetchModels()
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Picker("", selection: $selectedModel) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.top, 4)
                        }
                        
                        Text("Polls the latest models from the Google AI registry to ensure you have access to the newest versions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // App-Specific Section
                    AppSpecificSettingsView()
                    
                    Divider()
                    
                    // Search Depth Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Semantic Search Depth")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Slider(value: Binding(get: {
                                Double(semanticSearchDepth)
                            }, set: { newValue in
                                semanticSearchDepth = Int(newValue)
                            }), in: 200...2000, step: 50)
                            
                            Text("\(semanticSearchDepth)")
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        
                        Text("Higher values search further back in history but use more AI tokens (max 2000).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Data Management Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Management")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Label("History Retention", systemImage: "clock.arrow.2.circlepath")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Picker("", selection: $historyRetentionDays) {
                                Text("7 Days").tag(7)
                                Text("30 Days").tag(30)
                                Text("90 Days").tag(90)
                                Text("180 Days (6 mo)").tag(180)
                                Text("1 Year").tag(365)
                                Text("Forever").tag(0)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                        
                        Text("Controls how long clipboard items are kept before automatic deletion.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .frame(width: 380, height: 500)
        .onAppear {
            if availableModels.isEmpty {
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
                    
                    // Ensure the current selection is valid or default it
                    if !models.contains(selectedModel) && !models.isEmpty {
                        if models.contains("gemini-1.5-flash") {
                            self.selectedModel = "gemini-1.5-flash"
                        } else {
                            self.selectedModel = models.first ?? ""
                        }
                    }
                    self.isLoadingModels = false
                    
                    // Hide success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.showSuccessMessage = false
                        }
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
    
    func updateLoginItem(enabled: Bool) {
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
