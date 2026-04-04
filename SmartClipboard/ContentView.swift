import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @Query(sort: \ClipboardItem.timestamp, order: .reverse) private var history: [ClipboardItem]
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResults: [ClipboardItem] = []
    
    enum Field {
        case search
    }
    @FocusState private var focusedField: Field?
    
    // User Settings
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-1.5-flash"
    @AppStorage("semanticSearchDepth") private var semanticSearchDepth: Int = 200
    
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
                    .onAppear {
                        focusedField = .search
                    }
            }
        }
        .frame(width: 380, height: 500)
        .onAppear {
            focusedField = .search
        }
        .onChange(of: showingSettings) { newValue in
            if !newValue {
                // Focus search bar when returning from settings
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .search
                }
            }
        }
    }
    
    var mainView: some View {
        VStack(spacing: 0) {
            // Header with Search and Settings
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                        .padding(.leading, 8)
                    
                    TextField("Search instantly, or hit Return for AI search...", text: $searchQuery)
                        .textFieldStyle(PlainTextFieldStyle())
                        .focused($focusedField, equals: .search)
                        .onChange(of: searchQuery) { _ in
                            performLocalSearch()
                        }
                        .onSubmit {
                            performAISearch()
                        }
                    
                    if isSearching {
                        ProgressView().scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    } else if !searchQuery.isEmpty {
                        Button(action: { 
                            searchQuery = "" 
                            performLocalSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .padding(.trailing, 8)
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
                List {
                    let items = displayItems
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            if index < 10 {
                                Text("\(index == 9 ? 0 : index + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 15)
                                    .padding(4)
                                    .background(Color(NSColor.quaternaryLabelColor))
                                    .cornerRadius(4)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(formatTimestamp(item.timestamp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(item.content)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(3)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            clipboardManager.paste(content: item.content)
                        }
                    }
                }
                .listStyle(.sidebar)
                .background {
                    // Invisible buttons for keyboard shortcuts
                    ZStack {
                        let items = displayItems
                        // Shortcut for items 1-9
                        ForEach(0..<min(items.count, 9), id: \.self) { i in
                            Button("") {
                                clipboardManager.paste(content: items[i].content)
                            }
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                            .opacity(0)
                        }
                        // Shortcut for item 10 (Cmd+0)
                        if items.count >= 10 {
                            Button("") {
                                clipboardManager.paste(content: items[9].content)
                            }
                            .keyboardShortcut("0", modifiers: .command)
                            .opacity(0)
                        }
                    }
                }
            }
        }
    }
    
    func performLocalSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        
        // Instant Local Search
        self.searchResults = history.filter { item in
            // 1. Text match
            if item.content.localizedCaseInsensitiveContains(searchQuery) { return true }
            
            let isToday = Calendar.current.isDateInToday(item.timestamp)
            
            // 2. Natural relative day matching
            let lowerQuery = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
            if "yesterday".hasPrefix(lowerQuery) && lowerQuery.count >= 4 {
                if Calendar.current.isDateInYesterday(item.timestamp) { return true }
            }
            if "today".hasPrefix(lowerQuery) && lowerQuery.count >= 3 {
                if isToday { return true }
            }
            
            let timeStr = Self.timeFormatter.string(from: item.timestamp)
            
            // 3. Exact time string? Only match if it's today
            if isToday && timeStr.localizedCaseInsensitiveContains(searchQuery) {
                return true
            }
            
            // 4. Date-only match (e.g. searching "4/4/26") works for all days
            let dateOnlyStr = Self.dateFormatter.string(from: item.timestamp)
            if dateOnlyStr.localizedCaseInsensitiveContains(searchQuery) {
                return true
            }
            
            // 5. Full string match (date + time)
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
    
    func performAISearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        Task {
            do {
                let intent = try await geminiService.parseSearchIntent(
                    query: searchQuery,
                    history: history,
                    apiKey: apiKey,
                    modelName: selectedModel,
                    searchDepth: semanticSearchDepth
                )
                
                await MainActor.run {
                    var filtered = self.history
                    
                    // If AI performed a semantic match specifically over the items, use those!
                    if let semanticIds = intent.semanticMatchIds, !semanticIds.isEmpty {
                        let semanticSet = Set(semanticIds)
                        filtered = filtered.filter { semanticSet.contains($0.id) }
                    } else {
                        if let start = intent.startDate, let end = intent.endDate {
                            filtered = filtered.filter { $0.timestamp >= start && $0.timestamp <= end }
                        }
                        
                        if let textQ = intent.textQuery, !textQ.isEmpty {
                            filtered = filtered.filter { $0.content.localizedCaseInsensitiveContains(textQ) }
                        }
                    }
                    
                    self.searchResults = filtered
                    self.isSearching = false
                }
            } catch {
                print("Search error: \(error)")
                await MainActor.run { self.isSearching = false }
            }
        }
    }
}
