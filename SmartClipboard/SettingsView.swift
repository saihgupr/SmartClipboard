import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-1.5-flash"
    
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
                    
                    Divider()
                    
                    // Danger Zone
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Danger Zone")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                        
                        Button(role: .destructive, action: { showClearConfirmation = true }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear Clipboard History")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .alert("Clear History", isPresented: $showClearConfirmation) {
                            Button("Cancel", role: .cancel) {}
                            Button("Clear All", role: .destructive) {
                                clearHistory()
                            }
                        } message: {
                            Text("Are you sure you want to clear your entire clipboard history? This cannot be undone.")
                        }
                        
                        Text("Permanently deletes all saved clipboard data.")
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
    
    func clearHistory() {
        do {
            try modelContext.delete(model: ClipboardItem.self)
            try modelContext.save()
        } catch {
            print("Failed to clear history: \(error)")
        }
    }
}
