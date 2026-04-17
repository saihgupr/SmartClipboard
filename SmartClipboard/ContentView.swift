import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @Query(sort: \ClipboardItem.timestamp, order: .reverse) private var history: [ClipboardItem]
    
    let isInPopover: Bool
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResults: [ClipboardItem] = []
    
    @State private var selectedItemId: UUID?
    @FocusState private var isSearchFocused: Bool
    
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-1.5-flash"
    @AppStorage("semanticSearchDepth") private var semanticSearchDepth: Int = 200
    
    private let geminiService = GeminiService()
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
    
    private static let queryDateFormatters: [DateFormatter] = {
        let formats = ["M/d", "M-d", "M.d", "MMM d", "MMMM d", "d MMM", "d MMMM"]
        return formats.map { format in
            let df = DateFormatter()
            df.locale = Locale.current
            df.dateFormat = format
            return df
        }
    }()

    // ⚡ Bolt: Cache standaloneWeekdaySymbols to avoid O(N) allocations in local search filtering loops.
    // Expected impact: Eliminates continuous memory allocation overhead during keystrokes, reducing local search latency.
    private static let weekdaySymbols = Calendar.current.standaloneWeekdaySymbols

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
            // macOS Tahoe Polished Search Header
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13, weight: .medium))
                    
                    TextField("Search history...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onChange(of: searchQuery) { _, newValue in
                            // Security: Enforce input length limit (DoS risk)
                            if newValue.count > 2000 {
                                searchQuery = String(newValue.prefix(2000))
                            }
                            performLocalSearch()
                            if let firstId = displayItems.first?.id {
                                selectedItemId = firstId
                            }
                        }
                        .onSubmit {
                            if let id = selectedItemId, let item = displayItems.first(where: { $0.id == id }) {
                                clipboardManager.paste(item: item)
                            } else if let first = displayItems.first {
                                clipboardManager.paste(item: first)
                            }
                        }
                    
                    if isSearching {
                        ProgressView().scaleEffect(0.4).frame(width: 16, height: 16)
                    } else if !searchQuery.isEmpty {
                        Button(action: performAISearch) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(apiKey.isEmpty ? .secondary : .blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(apiKey.isEmpty)
                        .help(apiKey.isEmpty ? "API key required for AI Search (Configure in Settings)" : "AI Search")
                        .accessibilityLabel("AI Search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                
                if #available(macOS 13.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .accessibilityLabel("Settings")
                    .simultaneousGesture(TapGesture().onEnded {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NotificationCenter.default.post(name: .closeUI, object: nil)
                        }
                    })
                } else {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .accessibilityLabel("Settings")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16) 
            .padding(.bottom, 14)
            
            Divider()
                .opacity(0.5)
            
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

                        // ⚡ Bolt: Removed .enumerated() to prevent O(N) tuple array allocation on every render.
                        // Expected impact: Massively reduces UI thread lag and memory overhead when scrolling or typing queries with large clipboards.
                        let top10ItemIds = displayItems.prefix(10).map(\.id)

                        ForEach(displayItems) { item in
                            ClipboardRow(
                                item: item,
                                index: top10ItemIds.firstIndex(of: item.id),
                                isSelected: selectedItemId == item.id,
                                timestamp: formatTimestamp(item.timestamp, todayStart: todayStart, tomorrowStart: tomorrowStart, yesterdayStart: yesterdayStart)
                            )
                            .tag(item.id)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .onTapGesture {
                                selectedItemId = item.id
                                clipboardManager.paste(item: item)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation { clipboardManager.delete(item: item) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .accentColor(.blue)
                    .onChange(of: selectedItemId) { _, newValue in
                        if let id = newValue {
                            DispatchQueue.main.async {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 500)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow, cornerRadius: 12).ignoresSafeArea())
        .onAppear {
            setupKeyboardMonitor()
            isSearchFocused = true
            selectedItemId = displayItems.first?.id
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiWillShow)) { notification in
            // Only respond if the notification was intended for this specific instance
            guard let targetIsPopover = notification.userInfo?["isInPopover"] as? Bool,
                  targetIsPopover == self.isInPopover else { return }
            
            searchQuery = ""
            selectedItemId = history.first?.id
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
    }


    @State private var keyboardMonitor: Any?
    
    private func setupKeyboardMonitor() {
        if keyboardMonitor != nil { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Security: Don't intercept if Settings window is frontmost
            if NSApp.keyWindow?.title.contains("Settings") == true { return event }
            
            // Check if the event is targeted at the window containing this view
            // We use the first responder check to verify if we are indeed the active UI
            guard let keyWindow = NSApp.keyWindow,
                  let myWindow = event.window,
                  keyWindow == myWindow else { return event }
            
            // Use first responder check to avoid stale capture of SwiftUI @FocusState
            let isFocused = keyWindow.firstResponder is NSTextView
            
            // Handle specific navigation keys
            switch event.keyCode {
            case 125: // Down
                DispatchQueue.main.async {
                    let items = displayItems
                    guard !items.isEmpty else { return }
                    if let currentId = selectedItemId, let idx = items.firstIndex(where: { $0.id == currentId }) {
                        if idx < items.count - 1 {
                            selectedItemId = items[idx + 1].id
                        }
                    } else {
                        selectedItemId = items.first?.id
                    }
                }
                return nil
                
            case 126: // Up
                DispatchQueue.main.async {
                    let items = displayItems
                    guard !items.isEmpty else { return }
                    if let currentId = selectedItemId, let idx = items.firstIndex(where: { $0.id == currentId }) {
                        if idx > 0 {
                            selectedItemId = items[idx - 1].id
                        }
                    } else {
                        selectedItemId = items.first?.id
                    }
                }
                return nil
                
            case 36: // Enter
                // If focused on text field, only intercept if we want to trigger paste
                // Otherwise let the TextField handle its own submit
                if isFocused { return event }
                DispatchQueue.main.async {
                    if let id = selectedItemId, let item = displayItems.first(where: { $0.id == id }) {
                        clipboardManager.paste(item: item)
                    }
                }
                return nil
                
            default:
                // If not focused, check if we should auto-focus on character input
                if !isFocused, !event.modifierFlags.contains(.command), 
                   let chars = event.charactersIgnoringModifiers, chars.count == 1 {
                    let unicode = chars.unicodeScalars.first?.value ?? 0
                    if (unicode >= 32 && unicode < 127) || unicode > 160 {
                        DispatchQueue.main.async {
                            isSearchFocused = true
                        }
                        // Return event so it lands in the newly focused TextField
                        return event
                    }
                }
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
    
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .closeUI, object: nil)
        }
    }
    
    func performLocalSearch() {
        guard !searchQuery.isEmpty else { searchResults = []; return }
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        let lowerQuery = query.lowercased()
        let calendar = Calendar.current
        let now = Date()
        
        var qDay: Int?, qMonth: Int?, qWeekday: Int?
        for df in Self.queryDateFormatters {
            if let date = df.date(from: query) {
                qDay = calendar.component(.day, from: date)
                qMonth = calendar.component(.month, from: date)
                break
            }
        }
        if let idx = Self.weekdaySymbols.firstIndex(where: { $0.localizedCaseInsensitiveContains(query) }) { qWeekday = idx + 1 }
        
        let matchesYesterday = "yesterday".hasPrefix(lowerQuery) && lowerQuery.count >= 4
        let matchesToday = "today".hasPrefix(lowerQuery) && lowerQuery.count >= 3

        // ⚡ Bolt: Fast-paths must be strict. Don't trigger O(N) DateFormatter logic for strings that just happen to contain 'am' or '-'.
        // Expected impact: Eliminates O(N) lag on keystrokes when typing normal queries (e.g. "program", "bug-fix")
        let hasDigits = query.rangeOfCharacter(from: .decimalDigits) != nil

        let mightBeTime = hasDigits && (lowerQuery.contains("am") ||
                                        lowerQuery.contains("pm") ||
                                        query.contains(":"))

        let mightBeDateString = qMonth != nil ||
                                qWeekday != nil ||
                                (hasDigits && (query.contains("/") || query.contains("-")))

        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        self.searchResults = history.filter { item in
            if item.content.localizedCaseInsensitiveContains(query) { return true }
            
            let itemDate = item.timestamp
            
            if let qM = qMonth, let qD = qDay {
                // Use separate .component() calls to avoid allocating heavy DateComponents structs in loop
                let itemMonth = calendar.component(.month, from: itemDate)
                if itemMonth == qM {
                    let itemDay = calendar.component(.day, from: itemDate)
                    if itemDay == qD {
                        return true
                    }
                }
            }
            
            if let qW = qWeekday {
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
            
            if mightBeTime {
                let timeStr = Self.timeFormatter.string(from: itemDate)
                if timeStr.localizedCaseInsensitiveContains(query) {
                    if itemDate >= todayStart && itemDate < tomorrowStart { return true }
                    if query.contains(":") || lowerQuery.contains("am") || lowerQuery.contains("pm") {
                        return true
                    }
                }
            }

            if mightBeDateString {
                let fullStr = Self.fullFormatter.string(from: itemDate)
                if fullStr.localizedCaseInsensitiveContains(query) {
                    return true
                }
            }
            
            return false
        }
    }
    
    func performAISearch() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        Task {
            do {
                let intent = try await geminiService.parseSearchIntent(query: searchQuery, history: history, apiKey: apiKey, modelName: selectedModel, searchDepth: semanticSearchDepth)
                await MainActor.run {
                    var filtered = self.history
                    if let ids = intent.semanticMatchIds, !ids.isEmpty {
                        let set = Set(ids); filtered = filtered.filter { set.contains($0.id) }
                    } else {
                        if let s = intent.startDate, let e = intent.endDate { filtered = filtered.filter { $0.timestamp >= s && $0.timestamp <= e } }
                        if let t = intent.textQuery, !t.isEmpty { filtered = filtered.filter { $0.content.localizedCaseInsensitiveContains(t) } }
                    }
                    self.searchResults = filtered
                    self.selectedItemId = filtered.first?.id
                    self.isSearching = false
                }
            } catch { isSearching = false }
        }
    }
    
    private var accessibilityWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text("Accessibility Required").font(.caption.bold())
            Spacer()
            Button("Fix") {
                clipboardManager.requestAccessibilityPermission()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text(searchQuery.isEmpty ? "Clipboard is empty. Copy some text to get started." : (isSearching ? "Searching with AI..." : "No matches found."))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    isSearchFocused = true
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            } else {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString("Hello, SmartClipboard! 👋", forType: .string)
                } label: {
                    Label("Copy Sample Text", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
                .accessibilityLabel("Copy Sample Text")
                .help("Copy text to populate clipboard")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat = 0
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        
        if cornerRadius > 0 {
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.masksToBounds = true
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        if cornerRadius > 0 {
            nsView.layer?.cornerRadius = cornerRadius
        }
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int?
    let isSelected: Bool
    let timestamp: String
    
    var body: some View {
        HStack(spacing: 12) {
            if let index = index {
                Text("\(index == 9 ? 0 : index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .frame(width: 18, height: 18)
                    .background(isSelected ? Color.white.opacity(0.25) : Color(NSColor.quaternaryLabelColor))
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(timestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                
                Text(item.content)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .lineLimit(2)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}
