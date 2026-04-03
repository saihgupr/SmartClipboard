import SwiftUI

struct SettingsView: View {
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-1.5-flash"
    
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var errorMessage: String?
    
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
                    // API Key Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        SecureField("Enter your Gemini API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("If empty, a default evaluation key will be used.")
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
        Task {
            do {
                let models = try await geminiService.fetchModels(apiKey: apiKey)
                await MainActor.run {
                    self.availableModels = models
                    // Ensure the current selection is valid or default it
                    if !models.contains(selectedModel) && !models.isEmpty {
                        if models.contains("gemini-1.5-flash") {
                            self.selectedModel = "gemini-1.5-flash"
                        } else {
                            self.selectedModel = models.first ?? ""
                        }
                    }
                    self.isLoadingModels = false
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
