import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @Query(sort: \ClipboardItem.timestamp, order: .reverse) private var history: [ClipboardItem]
    
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
                        .onChange(of: searchQuery) { _, _ in
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
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("AI Search")
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
                } else {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
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

                        ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                            ClipboardRow(
                                item: item,
                                index: index,
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
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow).ignoresSafeArea())
        .onAppear {
            setupKeyboardMonitor()
            isSearchFocused = true
            selectedItemId = displayItems.first?.id
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiWillShow)) { _ in
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
            // Check if THIS view is in the key window. This prevents double-monitoring.
            guard let keyWindow = NSApp.keyWindow,
                  let myWindow = event.window,
                  keyWindow == myWindow else { return event }
            
            // Don't intercept if Settings window is frontmost
            if keyWindow.title.contains("Settings") == true { return event }
            
            let items = displayItems
            switch event.keyCode {
            case 125: // Down
                guard !items.isEmpty else { return event }
                if let currentId = selectedItemId, let idx = items.firstIndex(where: { $0.id == currentId }) {
                    if idx < items.count - 1 {
                        selectedItemId = items[idx + 1].id
                    }
                } else {
                    selectedItemId = items.first?.id
                }
                return nil
            case 126: // Up
                guard !items.isEmpty else { return event }
                if let currentId = selectedItemId, let idx = items.firstIndex(where: { $0.id == currentId }) {
                    if idx > 0 {
                        selectedItemId = items[idx - 1].id
                    }
                } else {
                    selectedItemId = items.first?.id
                }
                return nil
            case 36: // Enter
                if isSearchFocused { return event }
                if let id = selectedItemId, let item = items.first(where: { $0.id == id }) {
                    clipboardManager.paste(item: item)
                    return nil
                }
            default:
                if !isSearchFocused, let chars = event.charactersIgnoringModifiers, chars.count == 1 {
                    let unicode = chars.unicodeScalars.first?.value ?? 0
                    if (unicode >= 32 && unicode < 127) || unicode > 160 {
                        isSearchFocused = true
                        // DO NOT manually append or return nil. 
                        // Returning the event allows the TextField to receive it normally.
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
                let comps = calendar.dateComponents([.month, .day], from: date)
                qDay = comps.day; qMonth = comps.month; break
            }
        }
        if let idx = Calendar.current.standaloneWeekdaySymbols.firstIndex(where: { $0.localizedCaseInsensitiveContains(query) }) { qWeekday = idx + 1 }
        
        let matchesYesterday = "yesterday".hasPrefix(lowerQuery) && lowerQuery.count >= 4
        let matchesToday = "today".hasPrefix(lowerQuery) && lowerQuery.count >= 3
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        self.searchResults = history.filter { item in
            if item.content.localizedCaseInsensitiveContains(query) { return true }
            let d = item.timestamp
            if let m = qMonth, let day = qDay {
                let comps = calendar.dateComponents([.month, .day], from: d)
                if comps.month == m && comps.day == day { return true }
            }
            if let w = qWeekday, calendar.component(.weekday, from: d) == w { return true }
            if matchesYesterday, d >= yesterdayStart && d < todayStart { return true }
            if matchesToday, d >= todayStart && d < tomorrowStart { return true }
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
                .font(.system(size: 32)).foregroundColor(.secondary.opacity(0.3))
            Text(searchQuery.isEmpty ? "Clipboard is empty" : "No matches found").foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let timestamp: String
    
    var body: some View {
        HStack(spacing: 12) {
            if index < 10 {
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
