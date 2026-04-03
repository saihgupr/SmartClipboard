import SwiftUI

struct ContentView: View {
    @StateObject private var clipboardManager = ClipboardManager()
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResults: [ClipboardItem] = []
    
    // User Settings
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-1.5-flash"
    
    @State private var showingSettings = false
    
    private let geminiService = GeminiService()

    var displayItems: [ClipboardItem] {
        searchQuery.isEmpty ? clipboardManager.history : searchResults
    }

    var body: some View {
        ZStack {
            if showingSettings {
                SettingsView(onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingSettings = false
                    }
                })
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                .zIndex(1)
            } else {
                mainView
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            }
        }
        .frame(width: 380, height: 500)
    }
    
    var mainView: some View {
        VStack(spacing: 0) {
            // Header with Search and Settings
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(isSearching ? .blue : .secondary)
                        .font(.system(size: 14))
                    
                    TextField("Ask AI to find anything...", text: $searchQuery)
                        .textFieldStyle(PlainTextFieldStyle())
                        .onChange(of: searchQuery) { _ in
                            performSearch()
                        }
                    
                    if isSearching {
                        ProgressView().scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    } else if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingSettings = true
                    }
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("AI Settings")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Clipboard List
            if displayItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(searchQuery.isEmpty ? "Clipboard is empty" : "No matches found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(displayItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(item.content)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(3)
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clipboardManager.copyToClipboard(item: item)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
    
    func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        Task {
            do {
                let matchedIds = try await geminiService.search(
                    query: searchQuery, 
                    history: clipboardManager.history,
                    apiKey: apiKey,
                    modelName: selectedModel
                )
                await MainActor.run {
                    self.searchResults = self.clipboardManager.history.filter { matchedIds.contains($0.id) }
                    self.isSearching = false
                }
            } catch {
                print("Search error: \(error)")
                await MainActor.run { self.isSearching = false }
            }
        }
    }
}
