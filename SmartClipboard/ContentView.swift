import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @Query(sort: \ClipboardItem.timestamp, order: .reverse) private var history: [ClipboardItem]
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResults: [ClipboardItem] = []
    @State private var selectedIndex: Int = -1
    
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
    
    // ⚡ Bolt Optimization: Extract expensive formatter and calendar properties into static variables
    // to prevent continuous allocations on every keystroke in performLocalSearch.
    private static let queryDateFormatters: [DateFormatter] = {
        let formats = [
            "M/d", "M-d", "M.d",
            "MMM d", "MMMM d",
            "d MMM", "d MMMM"
        ]
        return formats.map { format in
            let df = DateFormatter()
            df.locale = Locale.current
            df.dateFormat = format
            return df
        }
    }()

    private static let weekdays: [String] = Calendar.current.standaloneWeekdaySymbols
    private static let shortWeekdays: [String] = Calendar.current.shortStandaloneWeekdaySymbols

    // Format timestamp for UI depending on how old it is
    // ⚡ Bolt Optimization: Use pre-computed date boundaries for direct Date comparisons
    // instead of Calendar.current.isDateInToday(date) inside the loop, significantly
    // improving render performance for large lists.
    private func formatTimestamp(_ date: Date, todayStart: Date, tomorrowStart: Date, yesterdayStart: Date) -> String {
        if date >= todayStart && date < tomorrowStart {
            return Self.timeFormatter.string(from: date)
        } else if date >= yesterdayStart && date < todayStart {
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
                        if !displayItems.isEmpty {
                            selectedIndex = 0
                        }
                    }
            }
        }
        .frame(width: 380, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            focusedField = .search
            if !displayItems.isEmpty {
                selectedIndex = 0
            }
        }
        .onChange(of: showingSettings) { oldValue, newValue in
            if !newValue {
                // Focus search bar when returning from settings
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .search
                }
            }
        }
        .onAppear {
            setupKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }
    
    @State private var keyboardMonitor: Any?
    
    private func setupKeyboardMonitor() {
        removeKeyboardMonitor()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Handle only navigation and paste if settings is not shown
            guard !showingSettings else { return event }
            
            let items = displayItems
            guard !items.isEmpty else { return event }
            
            switch event.keyCode {
            case 125: // Down
                if selectedIndex < items.count - 1 {
                    selectedIndex += 1
                }
                return nil
            case 126: // Up
                if selectedIndex > 0 {
                    selectedIndex -= 1
                } else if selectedIndex == 0 {
                    selectedIndex = -1
                    focusedField = .search
                }
                return nil
            case 36: // Enter
                if selectedIndex >= 0 && selectedIndex < items.count {
                    clipboardManager.paste(item: items[selectedIndex])
                    return nil
                }
                return event // Let search field submit if nothing selected
            default:
                break
            }
            
            return event
        }
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
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
                        .onChange(of: searchQuery) { oldValue, newValue in
                            performLocalSearch()
                            selectedIndex = displayItems.isEmpty ? -1 : 0
                        }
                        .onSubmit {
                            if selectedIndex < 0 {
                                performAISearch()
                            }
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
                        .accessibilityLabel("Clear search")
                        .help("Clear search")
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
                .accessibilityLabel("Settings")
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

                    if searchQuery.isEmpty {
                        Text("Copy some text to get started")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    } else {
                        Button("Clear Search") {
                            searchQuery = ""
                            performLocalSearch()
                            selectedIndex = displayItems.isEmpty ? -1 : 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        // Dummy element at the top to scroll to
                        Color.clear
                            .frame(height: 0)
                            .id("top")
                            .listRowInsets(EdgeInsets())
                        
                        let items = displayItems
                    let now = Date()
                    let calendar = Calendar.current
                    let todayStart = calendar.startOfDay(for: now)
                    let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                    let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

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
                                Text(formatTimestamp(item.timestamp, todayStart: todayStart, tomorrowStart: tomorrowStart, yesterdayStart: yesterdayStart))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(item.content)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(3)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(selectedIndex == index ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
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
                    } // closes ForEach
                    } // closes List
                    .listStyle(.sidebar)
                    .onReceive(NotificationCenter.default.publisher(for: .uiWillShow)) { _ in
                        searchQuery = ""
                        // Small delay to ensure state updates before selecting/scrolling
                        DispatchQueue.main.async {
                            if !history.isEmpty {
                                selectedIndex = 0
                                proxy.scrollTo("top", anchor: .top)
                            } else {
                                selectedIndex = -1
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { oldValue, newValue in
                        let items = displayItems
                        if newValue >= 0 && newValue < items.count {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(items[newValue].id)
                            }
                        }
                    }
                } // closes ScrollViewReader
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
        _ = calendar.component(.year, from: now)
        
        var queryDay: Int?
        var queryMonth: Int?
        var queryWeekday: Int? // 1=Sun, 2=Mon...
        
        // ⚡ Bolt Optimization: Use statically allocated formatters to avoid ICU cache invalidation
        for df in Self.queryDateFormatters {
            if let date = df.date(from: query) {
                let comps = calendar.dateComponents([.month, .day], from: date)
                queryDay = comps.day
                queryMonth = comps.month
                break
            }
        }
        
        // Try parsing weekday using static symbol arrays
        if let index = Self.weekdays.firstIndex(where: { $0.localizedCaseInsensitiveContains(query) }) {
            queryWeekday = index + 1
        } else if let index = Self.shortWeekdays.firstIndex(where: { $0.localizedCaseInsensitiveContains(query) }) {
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

        // ⚡ Bolt Performance Optimization:
        // Pre-compute date boundaries to avoid calling slow Calendar operations inside the filter loop.
        // Direct Date comparisons are orders of magnitude faster than calendar.isDateInToday(itemDate).
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

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
                if itemDate >= yesterdayStart && itemDate < todayStart { return true }
            }
            if matchesToday {
                if itemDate >= todayStart && itemDate < tomorrowStart { return true }
            }
            
            if mightBeTimeOrDate {
                // E. Time-only match (e.g. "10:30")
                let timeStr = Self.timeFormatter.string(from: itemDate)
                if timeStr.localizedCaseInsensitiveContains(query) {
                    // If it's today, it's a very strong match
                    if itemDate >= todayStart && itemDate < tomorrowStart { return true }
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
                    self.selectedIndex = filtered.isEmpty ? -1 : 0
                    self.isSearching = false
                }
            } catch {
                print("Search error: \(error)")
                await MainActor.run { self.isSearching = false }
            }
        }
    }
}
