import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @Query(sort: \ClipboardItem.timestamp, order: .reverse) private var history: [ClipboardItem]
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var isAIMode = false
    @State private var searchResults: [ClipboardItem] = []
    
    // User Settings
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-1.5-flash"
    
    @State private var showingSettings = false
    
    private let geminiService = GeminiService()
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .none
        f.dateStyle = .short
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
    
    // Format timestamp for UI depending on how old it is
    private func formatTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday, " + Self.timeFormatter.string(from: date)
        } else {
            return Self.fullFormatter.string(from: date)
        }
    }

    var displayItems: [ClipboardItem] {
        searchQuery.isEmpty ? history : searchResults
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
                    Button(action: {
                        isAIMode.toggle()
                        if !searchQuery.isEmpty {
                            performSearch()
                        }
                    }) {
                        Image(systemName: "sparkles")
                            .foregroundColor(isAIMode ? .blue : .secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle AI Search (Press Return to search)")
                    
                    TextField(isAIMode ? "Ask AI to find dates & topics..." : "Search clipboard instantly...", text: $searchQuery)
                        .textFieldStyle(PlainTextFieldStyle())
                        .onChange(of: searchQuery) { _ in
                            if !isAIMode {
                                performSearch()
                            }
                        }
                        .onSubmit {
                            if isAIMode {
                                performSearch()
                            }
                        }
                    
                    if isSearching {
                        ProgressView().scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    } else if !searchQuery.isEmpty {
                        Button(action: { 
                            searchQuery = "" 
                            if !isAIMode { performSearch() }
                        }) {
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
                        Text(formatTimestamp(item.timestamp))
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
        
        if isAIMode {
            isSearching = true
            Task {
                do {
                    let intent = try await geminiService.parseSearchIntent(
                        query: searchQuery,
                        apiKey: apiKey,
                        modelName: selectedModel
                    )
                    
                    await MainActor.run {
                        var filtered = self.history
                        
                        if let start = intent.startDate, let end = intent.endDate {
                            filtered = filtered.filter { $0.timestamp >= start && $0.timestamp <= end }
                        }
                        
                        if let textQ = intent.textQuery, !textQ.isEmpty {
                            filtered = filtered.filter { $0.content.localizedCaseInsensitiveContains(textQ) }
                        }
                        
                        self.searchResults = filtered
                        self.isSearching = false
                    }
                } catch {
                    print("Search error: \(error)")
                    await MainActor.run { self.isSearching = false }
                }
            }
        } else {
            // Instant Local Search
            self.searchResults = history.filter { item in
                // 1. Text match
                if item.content.localizedCaseInsensitiveContains(searchQuery) { return true }
                
                let isToday = Calendar.current.isDateInToday(item.timestamp)
                let timeStr = Self.timeFormatter.string(from: item.timestamp)
                
                // 2. Exact time string? Only match if it's today
                if isToday && timeStr.localizedCaseInsensitiveContains(searchQuery) {
                    return true
                }
                
                // 3. Date-only match (e.g. searching "4/4/26") works for all days
                let dateOnlyStr = Self.dateFormatter.string(from: item.timestamp)
                if dateOnlyStr.localizedCaseInsensitiveContains(searchQuery) {
                    return true
                }
                
                // 4. Full string match (date + time)
                let fullStr = Self.fullFormatter.string(from: item.timestamp)
                if fullStr.localizedCaseInsensitiveContains(searchQuery) {
                    // Stop it from matching if the query was PURELY the time string
                    if timeStr.localizedCaseInsensitiveContains(searchQuery) {
                        return false 
                    }
                    return true
                }
                
                return false
            }
        }
    }
}
