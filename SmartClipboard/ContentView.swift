import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @Query(sort: \ClipboardItem.timestamp, order: .reverse) private var history: [ClipboardItem]
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResults: [ClipboardItem] = []
    
    // We'll use the item ID for selection
    @State private var selectedItemId: UUID?
    @FocusState private var isSearchFocused: Bool
    
    // User Settings
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-1.5-flash"
    @AppStorage("semanticSearchDepth") private var semanticSearchDepth: Int = 200
    
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
        VStack(spacing: 0) {
            // macOS Tahoe Native Search Header
            HStack {
                TextField("Search items...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onChange(of: searchQuery) { _, _ in
                        performLocalSearch()
                        selectedItemId = displayItems.first?.id
                    }
                    .onSubmit {
                        if let id = selectedItemId, let item = displayItems.first(where: { $0.id == id }) {
                            clipboardManager.paste(item: item)
                        }
                    }
                
                if isSearching {
                    ProgressView().scaleEffect(0.5).frame(width: 20, height: 20)
                } else if !searchQuery.isEmpty {
                    Button(action: performAISearch) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("AI Search")
                }
                
                if #available(macOS 13.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                } else {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if !clipboardManager.hasAccessibilityPermission {
                accessibilityWarning
            }
            
            // Clipboard List
            if displayItems.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selectedItemId) {
                        let now = Date()
                        let calendar = Calendar.current
                        let todayStart = calendar.startOfDay(for: now)
                        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

                        ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 12) {
                                if index < 10 {
                                    Text("\(index == 9 ? 0 : index + 1)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(selectedItemId == item.id ? .white.opacity(0.8) : .secondary)
                                        .frame(width: 15)
                                        .padding(4)
                                        .background(selectedItemId == item.id ? Color.white.opacity(0.2) : Color(NSColor.quaternaryLabelColor))
                                        .cornerRadius(4)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatTimestamp(item.timestamp, todayStart: todayStart, tomorrowStart: tomorrowStart, yesterdayStart: yesterdayStart))
                                        .font(.caption)
                                        .foregroundColor(selectedItemId == item.id ? .white.opacity(0.8) : .secondary)
                                    
                                    Text(item.content)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(3)
                                        .foregroundColor(selectedItemId == item.id ? .white : .primary)
                                }
                            }
                            .tag(item.id)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItemId = item.id
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
                    .onChange(of: selectedItemId) { _, newValue in
                        if let id = newValue {
                            proxy.scrollTo(id)
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            isSearchFocused = true
            setupKeyboardMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiWillShow)) { _ in
            searchQuery = ""
            isSearchFocused = true
            DispatchQueue.main.async {
                selectedItemId = history.first?.id
            }
        }
    }

    @State private var keyboardMonitor: Any?
    
    private func setupKeyboardMonitor() {
        if keyboardMonitor != nil { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let items = displayItems
            guard !items.isEmpty else { return event }
            
            switch event.keyCode {
            case 125: // Down
                if let currentId = selectedItemId,
                   let currentIndex = items.firstIndex(where: { $0.id == currentId }),
                   currentIndex < items.count - 1 {
                    selectedItemId = items[currentIndex + 1].id
                    return nil
                } else if selectedItemId == nil {
                    selectedItemId = items.first?.id
                    return nil
                }
            case 126: // Up
                if let currentId = selectedItemId,
                   let currentIndex = items.firstIndex(where: { $0.id == currentId }),
                   currentIndex > 0 {
                    selectedItemId = items[currentIndex - 1].id
                    return nil
                }
            default:
                break
            }
            return event
        }
    }
    
    private var accessibilityWarning: some View {
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
    }
    
    private var emptyStateView: some View {
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
                    selectedItemId = displayItems.first?.id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    
    func performLocalSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        let lowerQuery = query.lowercased()
        
        let calendar = Calendar.current
        let now = Date()
        
        var queryDay: Int?
        var queryMonth: Int?
        var queryWeekday: Int?
        
        for df in Self.queryDateFormatters {
            if let date = df.date(from: query) {
                let comps = calendar.dateComponents([.month, .day], from: date)
                queryDay = comps.day
                queryMonth = comps.month
                break
            }
        }
        
        if let index = Self.weekdays.firstIndex(where: { $0.localizedCaseInsensitiveContains(query) }) {
            queryWeekday = index + 1
        } else if let index = Self.shortWeekdays.firstIndex(where: { $0.localizedCaseInsensitiveContains(query) }) {
            queryWeekday = index + 1
        }

        let matchesYesterday = "yesterday".hasPrefix(lowerQuery) && lowerQuery.count >= 4
        let matchesToday = "today".hasPrefix(lowerQuery) && lowerQuery.count >= 3

        let mightBeTimeOrDate = queryMonth != nil ||
                                queryWeekday != nil ||
                                lowerQuery.contains("am") ||
                                lowerQuery.contains("pm") ||
                                query.contains("/") ||
                                query.contains("-") ||
                                query.contains(":")

        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        self.searchResults = history.filter { item in
            if item.content.localizedCaseInsensitiveContains(query) { return true }
            
            let itemDate = item.timestamp
            
            if let qM = queryMonth, let qD = queryDay {
                let itemComps = calendar.dateComponents([.month, .day], from: itemDate)
                if itemComps.month == qM && itemComps.day == qD {
                    return true
                }
            }
            
            if let qW = queryWeekday {
                let itemWeekday = calendar.component(.weekday, from: itemDate)
                if itemWeekday == qW {
                    return true
                }
            }
            
            if matchesYesterday {
                if itemDate >= yesterdayStart && itemDate < todayStart { return true }
            }
            if matchesToday {
                if itemDate >= todayStart && itemDate < tomorrowStart { return true }
            }
            
            if mightBeTimeOrDate {
                let timeStr = Self.timeFormatter.string(from: itemDate)
                if timeStr.localizedCaseInsensitiveContains(query) {
                    if itemDate >= todayStart && itemDate < tomorrowStart { return true }
                    if query.contains(":") || lowerQuery.contains("am") || lowerQuery.contains("pm") {
                        return true
                    }
                }

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
                    self.selectedItemId = filtered.first?.id
                    self.isSearching = false
                }
            } catch {
                print("Search error: \(error)")
                await MainActor.run { self.isSearching = false }
            }
        }
    }
}
