import SwiftUI

struct ContentView: View {
    @StateObject private var clipboardManager = ClipboardManager()
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResults: [ClipboardItem] = []
    
    private let geminiService = GeminiService()

    var displayItems: [ClipboardItem] {
        searchQuery.isEmpty ? clipboardManager.history : searchResults
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(isSearching ? .blue : .secondary)
                
                TextField("Ask AI to find anything...", text: $searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchQuery) { _ in
                        performSearch()
                    }
                
                if isSearching {
                    ProgressView().scaleEffect(0.5)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Clipboard List
            if displayItems.isEmpty {
                Text(searchQuery.isEmpty ? "Clipboard is empty" : "No matches found")
                    .foregroundColor(.secondary)
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
                        // Optional: Add a visual flash or sound here to indicate it copied!
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 380, height: 500) // Fixed size for the popover
    }
    
    func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        Task {
            do {
                let matchedIds = try await geminiService.search(query: searchQuery, history: clipboardManager.history)
                DispatchQueue.main.async {
                    self.searchResults = self.clipboardManager.history.filter { matchedIds.contains($0.id) }
                    self.isSearching = false
                }
            } catch {
                print("Search error: \(error)")
                DispatchQueue.main.async { self.isSearching = false }
            }
        }
    }
}
