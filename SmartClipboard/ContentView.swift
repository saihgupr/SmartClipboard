import SwiftUI
import SwiftData
import AppKit

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
        .onChange(of: showingSettings) {
            if !showingSettings {
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
                        .onChange(of: searchQuery) {
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
            
            if !clipboardManager.hasAccessibilityPermission {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Accessibility Required")
                            .font(.headline)
                        Spacer()
                        Button("Fix") {
                            clipboardManager.requestAccessibilityPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    Text("Enable SmartClipboard in System Settings > Privacy > Accessibility to use global shortcuts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                
                Divider()
            }
            
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
                            clipboardManager.paste(item: item)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation {
                                    clipboardManager.delete(item: item)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
    
    func performLocalSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        let lowerQuery = query.lowercased()
        
        // --- 1. Attempt to parse query as a date/time ---
        // We'll ignore the year for most matches since history is short.
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        
        // Try multiple formats
        let formats = [
            "M/d", "M-d", "M.d",
            "MMM d", "MMMM d",
            "d MMM", "d MMMM"
        ]
        
        var queryDay: Int?
        var queryMonth: Int?
        var queryWeekday: Int? // 1=Sun, 2=Mon...
        
        let df = DateFormatter()
        df.locale = Locale.current
        
        for format in formats {
            df.dateFormat = format
            if let date = df.date(from: query) {
                let comps = calendar.dateComponents([.month, .day], from: date)
                queryDay = comps.day
                queryMonth = comps.month
                break
            }
        }
        
        // Try parsing weekday
        let weekdays = calendar.standaloneWeekdaySymbols // ["Sunday", "Monday", ...]
        let shortWeekdays = calendar.shortStandaloneWeekdaySymbols // ["Sun", "Mon", ...]
        if let index = weekdays.firstIndex(where: { $0.localizedCaseInsensitiveContains(query) }) {
            queryWeekday = index + 1
        } else if let index = shortWeekdays.firstIndex(where: { $0.localizedCaseInsensitiveContains(query) }) {
            queryWeekday = index + 1
        }

        // Precompute boolean prefixes to avoid string allocation/comparison per item
        let matchesYesterday = "yesterday".hasPrefix(lowerQuery) && lowerQuery.count >= 4
        let matchesToday = "today".hasPrefix(lowerQuery) && lowerQuery.count >= 3

        // Fast path: if the query doesn't look like a time or date at all, we can skip expensive date formatting
        // (digits, slashes, dashes, colons, am, pm)
        let containsDigits = query.rangeOfCharacter(from: .decimalDigits) != nil
        let mightBeTimeOrDate = containsDigits ||
                                lowerQuery.contains("am") ||
                                lowerQuery.contains("pm") ||
                                query.contains("/") ||
                                query.contains("-") ||
                                query.contains(":")

        // Instant Local Search
        self.searchResults = history.filter { item in
            // A. Direct Text Match
            if item.content.localizedCaseInsensitiveContains(query) { return true }
            
            let itemDate = item.timestamp
            
            // B. Explicit Month/Day match (Ignoring Year)
            if let qM = queryMonth, let qD = queryDay {
                let itemComps = calendar.dateComponents([.month, .day], from: itemDate)
                if itemComps.month == qM && itemComps.day == qD {
                    return true
                }
            }
            
            // C. Weekday match (e.g. "Monday")
            if let qW = queryWeekday {
                let itemWeekday = calendar.component(.weekday, from: itemDate)
                if itemWeekday == qW {
                    return true
                }
            }
            
            // D. Natural relative day matching (Today/Yesterday)
            if matchesYesterday {
                if calendar.isDateInYesterday(itemDate) { return true }
            }
            if matchesToday {
                if calendar.isDateInToday(itemDate) { return true }
            }
            
            if mightBeTimeOrDate {
                // E. Time-only match (e.g. "10:30")
                let timeStr = Self.timeFormatter.string(from: itemDate)
                if timeStr.localizedCaseInsensitiveContains(query) {
                    // If it's today, it's a very strong match
                    if calendar.isDateInToday(itemDate) { return true }
                    // Otherwise only match if the query explicitly included the colon or AM/PM
                    if query.contains(":") || lowerQuery.contains("am") || lowerQuery.contains("pm") {
                        return true
                    }
                }

                // F. Full formatted string fallback (M/D/YY etc.)
                let fullStr = Self.fullFormatter.string(from: itemDate)
                if fullStr.localizedCaseInsensitiveContains(query) {
                    return true
                }
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
