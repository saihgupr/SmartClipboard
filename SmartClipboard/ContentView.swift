import SwiftUI
import SwiftData
import AppKit
import ObjectiveC

private var shareDelegateKey: UInt8 = 0
private var actionTargetKey: UInt8 = 0

class ShareDelegate: NSObject, NSSharingServicePickerDelegate {
    let onDone: (NSSharingService?) -> Void
    init(onDone: @escaping (NSSharingService?) -> Void) { self.onDone = onDone }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onDone(service)
    }
}

class MenuItemActionTarget: NSObject {
    let action: () -> Void
    
    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }
    
    @objc func execute() {
        action()
    }
}

// MARK: - Helper UI Components

struct HoverIconHelper: View {
    let systemName: String
    let action: () -> Void
    let tooltip: String
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(tooltip)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct SparklesButton: View {
    let action: () -> Void
    let isDisabled: Bool
    let tooltip: String
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isDisabled ? .secondary.opacity(0.4) : (isHovered ? Color(red: 0.35, green: 0.65, blue: 0.98) : .secondary))
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovered && !isDisabled ? Color(red: 0.35, green: 0.65, blue: 0.98).opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isDisabled)
        .focusEffectDisabled()
        .help(tooltip)
        .onHover { hovering in
            if hovering {
                if !isDisabled { NSCursor.pointingHand.set() }
            } else {
                NSCursor.arrow.set()
            }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

struct KeycapBadge: View {
    let index: Int
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
            }
            
            Text(index == 9 ? "0" : "\(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.primary.opacity(0.8))
        }
        .frame(width: 18, height: 18)
    }
}

struct RowBackground: View {
    let isSelected: Bool
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isHovered ? Color.primary.opacity(0.06) : Color.clear, lineWidth: 0.5)
                    )
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct BackButton: View {
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                Text("Back")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isHovered ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}



// MARK: - Main ContentView

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @EnvironmentObject private var importManager: ImportManager
    @Query(sort: \ClipboardItem.timestamp, order: .reverse) private var history: [ClipboardItem]
    @Query(sort: \WorkflowSnippet.trigger, order: .forward) private var allWorkflows: [WorkflowSnippet]
    @State private var isShownAsPopover: Bool
    
    init(isInPopover: Bool) {
        self._isShownAsPopover = State(initialValue: isInPopover)
    }
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResults: [ClipboardItem] = []
    @State private var aiSearchError: String? = nil
    @State private var deletedItemIds: Set<UUID> = []
    @State private var pageLimit = 1
    private let pageSize = 40
    
    @State private var selectedItemId: UUID?
    @State private var selectedWorkflowId: UUID?
    @State private var selectedItemIds: Set<UUID> = []
    @State private var showingDetail = false
    @State private var showingSnippetDetail = false
    @State private var detailSnippet: WorkflowSnippet? = nil
    @State private var isSelectionFromMouse = false
    @State private var isQuickSelectActive = false
    @State private var isDismissSelected = false
    @State private var scrollToTopTrigger = false
    @FocusState private var isSearchFocused: Bool
    @State private var hostWindow: NSWindow?
    
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-2.5-flash"
    @AppStorage("aiSearchMode") private var aiSearchMode: String = "cloud"
    @AppStorage("ollamaUrl") private var ollamaUrl: String = "http://localhost:11434"
    @AppStorage("ollamaModel") private var ollamaModel: String = "gemma2:2b"
    @AppStorage("semanticSearchDepth") private var semanticSearchDepth: Int = 200
    @AppStorage("leftArrowAction") private var leftArrowAction: String = "googleSearch"
    @AppStorage("longLeftArrowAction") private var longLeftArrowAction: String = "delete"
    @AppStorage("themeStyle") private var themeStyle = "darkGlass"
    @AppStorage("enableSelectAllHotkeys") private var enableSelectAllHotkeys = false
    
    @State private var leftArrowDownTime: Date?
    @State private var leftArrowLongPressTriggered = false
    @State private var leftArrowDismissedDetail = false
    @State private var isSharingPickerOpen = false
    @State private var previousItemBeforeCopyId: UUID?
    @State private var nextItemBeforeCopyId: UUID?
    
    private let geminiService = GeminiService()
    private let ollamaService = OllamaService()
    
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

    private var allFilteredItems: [ClipboardItem] {
        let baseItems = searchQuery.isEmpty ? history : searchResults
        let filtered = baseItems.filter { !deletedItemIds.contains($0.id) }
        
        let pinned = filtered.filter { $0.isPinned }
        let unpinned = filtered.filter { !$0.isPinned }
        return pinned + unpinned
    }

    private var matchingWorkflows: [WorkflowSnippet] {
        let rawQuery = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !rawQuery.isEmpty else { return [] }
        
        if rawQuery.hasPrefix("/") {
            let cleanQuery = String(rawQuery.dropFirst())
            if cleanQuery.isEmpty {
                return allWorkflows
            }
            return allWorkflows.filter { item in
                let trig = item.trigger.lowercased()
                let cleanTrig = trig.hasPrefix("/") ? String(trig.dropFirst()) : trig
                let title = item.title.lowercased()
                
                let trigMatches = trig.hasPrefix(rawQuery) || cleanTrig.hasPrefix(cleanQuery)
                let titleMatches = title.hasPrefix(cleanQuery)
                
                return trigMatches || titleMatches
            }
        } else {
            return allWorkflows.filter { item in
                let trig = item.trigger.lowercased()
                let cleanTrig = trig.hasPrefix("/") ? String(trig.dropFirst()) : trig
                let title = item.title.lowercased()
                
                return cleanTrig.hasPrefix(rawQuery) || title.hasPrefix(rawQuery) || cleanTrig.contains(rawQuery) || title.contains(rawQuery)
            }
        }
    }

    var displayItems: [ClipboardItem] {
        Array(allFilteredItems.prefix(pageLimit * pageSize))
    }

    var top10ItemIds: [UUID] {
        Array(displayItems.prefix(10).map { $0.id })
    }

    var itemIndexMap: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: displayItems.enumerated().map { ($1.id, $0) })
    }

    private var displayItemIds: [UUID] {
        displayItems.map { $0.id }
    }

    var selectedItem: ClipboardItem? {
        if let id = selectedItemId, let idx = itemIndexMap[id], idx < displayItems.count {
            return displayItems[idx]
        }
        return nil
    }

    private func clearSearch() {
        searchQuery = ""
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func getBadgeIndex(index: Int) -> Int? {
        return index < 10 ? index : nil
    }

    var body: some View {
        ZStack {
            Button("") {
                clipboardManager.incognitoMode.toggle()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .buttonStyle(.plain)
            .opacity(0)
            
            VStack(spacing: 0) {
                headerViewArea
                
                if !clipboardManager.hasAccessibilityPermission {
                    accessibilityWarning
                }
                
                mainListContentArea
            }
            .padding(.top, isShownAsPopover ? 10 : 0)
            
            if showingDetail, let item = selectedItem {
                ClipboardDetailView(item: item, isSharingPickerOpen: $isSharingPickerOpen, isInPopover: isShownAsPopover) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingDetail = false
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            }
            
            if showingSnippetDetail, let snippet = detailSnippet {
                SnippetDetailView(snippet: snippet, isInPopover: isShownAsPopover) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingSnippetDetail = false
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .frame(width: 380, height: 500)
        .preferredColorScheme((themeStyle == "dark" || themeStyle == "darkGlass") ? .dark : (themeStyle == "light" ? .light : nil))
        .background(
            ZStack {
                if themeStyle == "dark" {
                    Color(red: 0.118, green: 0.118, blue: 0.118)
                } else if themeStyle == "light" {
                    Color(red: 0.96, green: 0.96, blue: 0.96)
                } else if themeStyle == "darkGlass" {
                    if #available(macOS 26.0, *) {
                        GlassEffectView(
                            style: .clear,
                            tintColor: NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.89),
                            cornerRadius: 16
                        )
                    } else {
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 16)
                        Color.black.opacity(0.4)
                    }
                    
                    // macOS Golden Gate liquid glass light-reflection overlay
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.clear,
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .cornerRadius(16)
                } else {
                    if #available(macOS 26.0, *) {
                        GlassEffectView(style: .regular, cornerRadius: 16)
                    } else {
                        VisualEffectView(material: .popover, blendingMode: .behindWindow, cornerRadius: 16)
                    }
                    
                    // macOS Golden Gate liquid glass light-reflection overlay
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.clear,
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .cornerRadius(16)
                }
                
                WindowAccessor { window in
                    self.hostWindow = window
                }
            }
            .clipShape(PopoverBubbleShape(showArrow: isShownAsPopover))
            .overlay(
                PopoverBubbleShape(showArrow: isShownAsPopover)
                    .stroke(
                        themeStyle == "light" ? Color.black.opacity(0.03) : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
            )
            .ignoresSafeArea()
        )
        .onAppear {
            setupKeyboardMonitor()
            isSearchFocused = true
            isSelectionFromMouse = false
            clearNavigationFallbacks()
            isDismissSelected = false
            selectedWorkflowId = nil
            selectedItemId = displayItems.first?.id
            if let firstId = selectedItemId {
                selectedItemIds = [firstId]
            }
            clipboardManager.visibleItems = displayItems
            scrollToTopTrigger.toggle()
        }
        .onDisappear {
            removeKeyboardMonitor()
            clipboardManager.visibleItems = []
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiWillShow)) { notification in
            let targetIsPopover = notification.userInfo?["isInPopover"] as? Bool ?? false
            let isQuickSelect = notification.userInfo?["isQuickSelect"] as? Bool ?? false
            isShownAsPopover = targetIsPopover
            isQuickSelectActive = isQuickSelect
            
            searchQuery = ""
            pageLimit = 1
            isSelectionFromMouse = false
            clearNavigationFallbacks()
            isDismissSelected = false
            selectedWorkflowId = nil
            
            // Set initial selection to Index 0
            if let firstItem = displayItems.first {
                selectedItemId = firstItem.id
                selectedItemIds = [firstItem.id]
            } else {
                selectedItemId = nil
                selectedItemIds = []
            }
            
            showingDetail = false
            showingSnippetDetail = false
            detailSnippet = nil
            leftArrowDismissedDetail = false
            isSharingPickerOpen = false
            
            removeKeyboardMonitor()
            setupKeyboardMonitor()
            
            clipboardManager.visibleItems = displayItems
            scrollToTopTrigger.toggle()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickSelectTriggerReleased)) { _ in
            if isQuickSelectActive {
                isQuickSelectActive = false
                if isDismissSelected {
                    isDismissSelected = false
                    NotificationCenter.default.post(name: .closeUI, object: nil)
                } else {
                    pasteCurrentSelection()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cancelQuickSelectMode)) { _ in
            isQuickSelectActive = false
            isDismissSelected = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .activateQuickSelectMode)) { _ in
            isQuickSelectActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickSelectNavigate)) { notification in
            guard isQuickSelectActive else { return }
            isSelectionFromMouse = false
            let delta = notification.userInfo?["delta"] as? Int ?? 0
            if delta > 0 {
                navigateNextItem()
            } else if delta < 0 {
                navigatePreviousItem()
            }
        }
        .onChange(of: displayItemIds) { _, _ in
            clipboardManager.visibleItems = displayItems
        }
    }

    @State private var keyboardMonitor: Any?

    private func pasteCurrentSelection() {
        if showingDetail { showingDetail = false }
        if showingSnippetDetail { showingSnippetDetail = false }
        
        if isDismissSelected {
            isDismissSelected = false
            NotificationCenter.default.post(name: .closeUI, object: nil)
            return
        }
        
        if let wfId = selectedWorkflowId,
           let snippet = matchingWorkflows.first(where: { $0.id == wfId }) {
            clipboardManager.paste(content: snippet.content)
        } else if let id = selectedItemId,
           let item = displayItems.first(where: { $0.id == id }) {
            clipboardManager.paste(item: item)
        } else if let first = displayItems.first {
            clipboardManager.paste(item: first)
        }
    }

    private func navigateNextItem() {
        if let fallbackId = nextItemBeforeCopyId {
            isDismissSelected = false
            selectedItemId = fallbackId
            selectedItemIds = [fallbackId]
            clearNavigationFallbacks()
            return
        }
        
        // If we are on Dismiss row in Quick Select, step down to top item or top snippet
        if isDismissSelected {
            withAnimation(.easeInOut(duration: 0.15)) {
                isDismissSelected = false
            }
            let snippets = matchingWorkflows
            if !snippets.isEmpty {
                selectedWorkflowId = snippets.first?.id
                selectedItemId = nil
                selectedItemIds = []
            } else if let firstId = displayItems.first?.id {
                selectedWorkflowId = nil
                selectedItemId = firstId
                selectedItemIds = [firstId]
            }
            return
        }
        
        let snippets = matchingWorkflows
        let items = displayItems
        
        // If a snippet is currently selected, move down within snippets or into clipboard
        if let wfId = selectedWorkflowId {
            if let idx = snippets.firstIndex(where: { $0.id == wfId }) {
                if idx < snippets.count - 1 {
                    // Move to next snippet
                    selectedWorkflowId = snippets[idx + 1].id
                } else {
                    // Fall into first clipboard item
                    selectedWorkflowId = nil
                    if let firstId = items.first?.id {
                        selectedItemId = firstId
                        selectedItemIds = [firstId]
                    }
                }
            }
            return
        }
        
        // No snippet selected — are we starting fresh with snippets present?
        if selectedItemId == nil && !snippets.isEmpty {
            selectedWorkflowId = snippets.first?.id
            return
        }
        
        // Navigate within clipboard items
        guard !items.isEmpty else { return }
        let indexMap = itemIndexMap
        if let currentId = selectedItemId,
           let idx = indexMap[currentId] {
            if idx < items.count - 1 {
                let nextId = items[idx + 1].id
                selectedItemId = nextId
                selectedItemIds = [nextId]
            } else if allFilteredItems.count > pageLimit * pageSize {
                withAnimation {
                    pageLimit += 1
                }
                DispatchQueue.main.async {
                    let newItems = self.displayItems
                    if idx + 1 < newItems.count {
                        let nextId = newItems[idx + 1].id
                        self.selectedItemId = nextId
                        self.selectedItemIds = [nextId]
                    }
                }
            }
        } else {
            let firstId = items.first?.id
            selectedItemId = firstId
            if let firstId = firstId {
                selectedItemIds = [firstId]
            }
        }
    }

    private func navigatePreviousItem() {
        if let fallbackId = previousItemBeforeCopyId {
            withAnimation(.easeInOut(duration: 0.15)) {
                isDismissSelected = false
            }
            selectedItemId = fallbackId
            selectedItemIds = [fallbackId]
            clearNavigationFallbacks()
            return
        }
        
        // Already at dismiss row
        if isDismissSelected {
            return
        }
        
        let snippets = matchingWorkflows
        let items = displayItems
        
        // If a snippet is currently selected, move up within snippets or to Dismiss
        if let wfId = selectedWorkflowId {
            if let idx = snippets.firstIndex(where: { $0.id == wfId }) {
                if idx > 0 {
                    selectedWorkflowId = snippets[idx - 1].id
                } else if isQuickSelectActive {
                    // Step up to Dismiss row
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isDismissSelected = true
                    }
                    selectedWorkflowId = nil
                    selectedItemId = nil
                    selectedItemIds = []
                }
            }
            return
        }
        
        // If on first clipboard item and snippets exist, move up into last snippet
        if let currentId = selectedItemId,
           let idx = itemIndexMap[currentId],
           idx == 0 {
            if !snippets.isEmpty {
                selectedItemId = nil
                selectedItemIds = []
                selectedWorkflowId = snippets.last?.id
                return
            } else if isQuickSelectActive {
                // Step up to Dismiss row
                withAnimation(.easeInOut(duration: 0.15)) {
                    isDismissSelected = true
                }
                selectedItemId = nil
                selectedItemIds = []
                return
            }
        }
        
        // Navigate within clipboard items
        guard !items.isEmpty else { return }
        let indexMap = itemIndexMap
        if let currentId = selectedItemId,
           let idx = indexMap[currentId] {
            if idx > 0 {
                let prevId = items[idx - 1].id
                selectedItemId = prevId
                selectedItemIds = [prevId]
            }
        } else {
            let firstId = items.first?.id
            selectedItemId = firstId
            if let firstId = firstId {
                selectedItemIds = [firstId]
            }
        }
    }

    private func saveFallbackNavigationTargets(for itemId: UUID) {
        let items = displayItems
        if let idx = itemIndexMap[itemId] {
            previousItemBeforeCopyId = idx > 0 ? items[idx - 1].id : nil
            nextItemBeforeCopyId = idx < items.count - 1 ? items[idx + 1].id : nil
        }
    }

    private func clearNavigationFallbacks() {
        previousItemBeforeCopyId = nil
        nextItemBeforeCopyId = nil
    }

    private func setupKeyboardMonitor() {
        if keyboardMonitor != nil { return }
        leftArrowDismissedDetail = false
        leftArrowDownTime = nil
        leftArrowLongPressTriggered = false
        isSharingPickerOpen = false
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [self] event in
            if NSApp.keyWindow?.title.contains("Settings") == true { return event }

            guard let keyWindow = NSApp.keyWindow,
                  let myWindow = self.hostWindow,
                  keyWindow === myWindow else { return event }

            if isSharingPickerOpen { return event }

            if event.type == .keyUp {
                if event.keyCode == 123 {
                    if leftArrowDismissedDetail {
                        leftArrowDismissedDetail = false
                        leftArrowDownTime = nil
                        leftArrowLongPressTriggered = false
                        return nil
                    }
                    if !leftArrowLongPressTriggered {
                        executeLeftArrowAction(leftArrowAction)
                    }
                    leftArrowDownTime = nil
                    leftArrowLongPressTriggered = false
                    return nil
                }
                return event
            }

            let isFocused = keyWindow.firstResponder is NSTextView

            let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isCommandOnly = relevantModifiers == .command
            let isOptionOnly = relevantModifiers == .option

            // MARK: - Option + V (Cmd+A, Cmd+V) and Option + C (Cmd+A, Cmd+C)
            if enableSelectAllHotkeys {
                let hasOption = event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control)
                if hasOption && (event.keyCode == 9 || event.keyCode == 8) { // kVK_ANSI_V = 9, kVK_ANSI_C = 8
                    if event.keyCode == 9 { // ⌥V - Select All & Paste
                        clipboardManager.selectAllAndPaste()
                    } else { // ⌥C - Select All & Copy
                        clipboardManager.selectAllAndCopy()
                    }
                    return nil
                }
            }


            if (isCommandOnly || isOptionOnly), let chars = event.charactersIgnoringModifiers, chars.count == 1 {
                if let num = Int(chars) {
                    let targetIndex: Int? = {
                        if num >= 1 && num <= 9 { return num - 1 }
                        if num == 0 { return 9 }
                        return nil
                    }()
                    if let targetIndex = targetIndex {
                        let snippets = matchingWorkflows
                        let items = displayItems
                        let totalCount = snippets.count + items.count
                        
                        if isCommandOnly {
                            if targetIndex < items.count {
                                let targetItem = items[targetIndex]
                                clipboardManager.paste(item: targetItem)
                                return nil
                            }
                        } else if isOptionOnly {
                            let countToPaste = min(targetIndex + 1, items.count)
                            if countToPaste > 0 {
                                let contentsToPaste = items[0..<countToPaste].map { $0.content }
                                clipboardManager.pasteMultipleContents(contentsToPaste)
                                return nil
                            }
                        }
                    }
                }
            }

            if isCommandOnly && event.keyCode == 8 {
                if showingDetail {
                    var hasSelection = false
                    if let textView = keyWindow.firstResponder as? NSTextView {
                        hasSelection = textView.selectedRange().length > 0
                    }
                    if !hasSelection {
                        if let item = selectedItem {
                            saveFallbackNavigationTargets(for: item.id)
                            clipboardManager.copyToClipboard(item: item)
                        }
                        return nil
                    }
                }
            }

            switch event.keyCode {
            case 125:
                isSelectionFromMouse = false
                navigateNextItem()
                return nil

            case 126:
                isSelectionFromMouse = false
                navigatePreviousItem()
                return nil

            case 124:
                if showingSnippetDetail {
                    // Right arrow inside snippet detail: nothing extra
                    return nil
                }
                // If a snippet is the active selection (slash query and workflow focused)
                let activeSnippet: WorkflowSnippet? = {
                    if let id = selectedWorkflowId {
                        return matchingWorkflows.first(where: { $0.id == id })
                    }
                    if searchQuery.hasPrefix("/") {
                        return matchingWorkflows.first
                    }
                    return nil
                }()
                if let snippet = activeSnippet {
                    detailSnippet = snippet
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingSnippetDetail = true
                    }
                    return nil
                }
                if !showingDetail {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingDetail = true
                    }
                    return nil
                } else {
                    triggerShare()
                    return nil
                }

            case 123:
                if showingDetail {
                    leftArrowDismissedDetail = true
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingDetail = false
                    }
                    return nil
                }
                
                if !event.isARepeat {
                    leftArrowDownTime = Date()
                    leftArrowLongPressTriggered = false
                } else if !leftArrowLongPressTriggered {
                    if let downTime = leftArrowDownTime,
                       Date().timeIntervalSince(downTime) > 0.4 {
                        executeLeftArrowAction(longLeftArrowAction)
                        leftArrowLongPressTriggered = true
                    }
                }
                return nil

            case 53: // Escape
                if showingSnippetDetail {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingSnippetDetail = false
                    }
                    return nil
                } else if showingDetail {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingDetail = false
                    }
                    return nil
                } else {
                    NotificationCenter.default.post(name: .closeUI, object: nil)
                    return nil
                }

            case 36:
                if isFocused { return event }
                if showingDetail { showingDetail = false }
                if isDismissSelected {
                    isQuickSelectActive = false
                    isDismissSelected = false
                    NotificationCenter.default.post(name: .closeUI, object: nil)
                    return nil
                }
                if let wfId = selectedWorkflowId,
                   let snippet = matchingWorkflows.first(where: { $0.id == wfId }) {
                    clipboardManager.paste(content: snippet.content)
                } else if let id = selectedItemId,
                   let item = displayItems.first(where: { $0.id == id }) {
                    clipboardManager.paste(item: item)
                }
                return nil

            default:
                if !isFocused, !event.modifierFlags.contains(.command),
                   let chars = event.charactersIgnoringModifiers, chars.count == 1 {
                    let unicode = chars.unicodeScalars.first?.value ?? 0
                    if (unicode >= 32 && unicode < 127) || unicode > 160 {
                        isSearchFocused = true
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
    
    private func executeLeftArrowAction(_ action: String) {
        isSelectionFromMouse = false
        guard let id = selectedItemId,
              let item = displayItems.first(where: { $0.id == id }) else { return }
        
        let targets: [ClipboardItem] = {
            if selectedItemIds.contains(id) {
                return displayItems.filter { selectedItemIds.contains($0.id) }
            } else {
                return [item]
            }
        }()
        
        // Copy and move to top of the list for all non-delete actions
        if action != "delete" {
            let joinedContent = targets.map { $0.content }.joined(separator: "\n")
            let now = Date()
            for (idx, target) in targets.reversed().enumerated() {
                target.timestamp = now.addingTimeInterval(Double(idx) * 0.001)
            }
            try? modelContext.save()
            clipboardManager.copyToClipboard(content: joinedContent, recordInDatabase: false)
        }
        
        if action == "quickCopy" {
            let currentItems = displayItems
            let indexMap = itemIndexMap
            let targetIndices = targets.compactMap { target in
                indexMap[target.id]
            }
            if let maxIndex = targetIndices.max(), maxIndex + 1 < currentItems.count {
                let nextId = currentItems[maxIndex + 1].id
                selectedItemId = nextId
                selectedItemIds = [nextId]
            }
        } else if action == "pin" {
            let allPinned = targets.allSatisfy { $0.isPinned }
            withAnimation {
                for target in targets {
                    target.isPinned = !allPinned
                }
                try? modelContext.save()
            }
        } else if action == "favorite" {
            let allFavorite = targets.allSatisfy { $0.isFavorite }
            withAnimation {
                for target in targets {
                    target.isFavorite = !allFavorite
                }
                try? modelContext.save()
            }
        } else if action == "pastePlainText" {
            let joinedContent = targets.map { $0.content }.joined(separator: "\n")
            // Already copied and moved to top above. We just need to simulate paste
            clipboardManager.paste(content: joinedContent)
        } else if action == "googleSearch" {
            let joinedContent = targets.map { $0.content }.joined(separator: " ")
            let query = joinedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: query),
               (url.scheme == "http" || url.scheme == "https") {
                NSWorkspace.shared.open(url)
                clipboardManager.onPaste?()
            } else if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                NSWorkspace.shared.open(url)
                clipboardManager.onPaste?()
            }
        } else if action == "delete" {
            let currentItems = displayItems
            let indexMap = itemIndexMap
            let targetIndices = targets.compactMap { target in
                indexMap[target.id]
            }
            let nextItem: ClipboardItem? = {
                guard let maxIndex = targetIndices.max() else { return nil }
                if maxIndex + 1 < currentItems.count {
                    return currentItems[maxIndex + 1]
                } else {
                    let minIndex = targetIndices.min() ?? 0
                    if minIndex > 0 {
                        return currentItems[minIndex - 1]
                    }
                }
                return nil
            }()
            withAnimation(.spring(response: 0.3)) {
                for target in targets {
                    deletedItemIds.insert(target.id)
                    clipboardManager.delete(item: target)
                    searchResults.removeAll { $0.id == target.id }
                    selectedItemIds.remove(target.id)
                }
                selectedItemId = nextItem?.id
                if let nextId = nextItem?.id {
                    selectedItemIds = [nextId]
                } else {
                    selectedItemIds = []
                    showingDetail = false
                }
            }
        }
    }
    
    private func handleRowClick(itemId: UUID, modifiers: NSEvent.ModifierFlags) {
        isSelectionFromMouse = true
        clearNavigationFallbacks()
        let items = displayItems
        let indexMap = itemIndexMap
        guard let clickedIndex = indexMap[itemId] else { return }
        
        if modifiers.contains(.shift) {
            if let firstSelectedId = selectedItemId,
               let anchorIndex = indexMap[firstSelectedId] {
                let start = min(anchorIndex, clickedIndex)
                let end = max(anchorIndex, clickedIndex)
                let rangeIds = items[start...end].map { $0.id }
                selectedItemIds = Set(rangeIds)
            } else {
                selectedItemIds = [itemId]
                selectedItemId = itemId
            }
        } else if modifiers.contains(.command) {
            if selectedItemIds.contains(itemId) {
                selectedItemIds.remove(itemId)
                if selectedItemId == itemId {
                    selectedItemId = selectedItemIds.first
                }
            } else {
                selectedItemIds.insert(itemId)
                selectedItemId = itemId
            }
        } else {
            selectedItemIds = [itemId]
            selectedItemId = itemId
        }
    }
    
    private func handleRowRightClick(itemId: UUID, modifiers: NSEvent.ModifierFlags) {
        isSelectionFromMouse = true
        if modifiers.contains(.shift) {
            handleRowClick(itemId: itemId, modifiers: modifiers)
        } else if modifiers.contains(.command) {
            handleRowClick(itemId: itemId, modifiers: modifiers)
        } else {
            if !selectedItemIds.contains(itemId) {
                selectedItemIds = [itemId]
                selectedItemId = itemId
            }
        }
    }
    
    private func showNativeContextMenu(for item: ClipboardItem) {
        let menu = NSMenu()
        
        let pasteTarget = MenuItemActionTarget {
            if self.selectedItemIds.contains(item.id) {
                let selectedItems = self.displayItems.filter { self.selectedItemIds.contains($0.id) }
                let joinedContent = selectedItems.map { $0.content }.joined(separator: "\n")
                self.clipboardManager.paste(content: joinedContent)
            } else {
                self.clipboardManager.paste(item: item)
            }
        }
        let pasteItem = NSMenuItem(title: "Paste Plain Text", action: #selector(MenuItemActionTarget.execute), keyEquivalent: "")
        pasteItem.target = pasteTarget
        pasteItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        objc_setAssociatedObject(pasteItem, &actionTargetKey, pasteTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(pasteItem)
        
        let detailTarget = MenuItemActionTarget {
            self.selectedItemId = item.id
            self.selectedItemIds = [item.id]
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.showingDetail = true
            }
        }
        let detailItem = NSMenuItem(title: "Clipboard Detail", action: #selector(MenuItemActionTarget.execute), keyEquivalent: "")
        detailItem.target = detailTarget
        detailItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        objc_setAssociatedObject(detailItem, &actionTargetKey, detailTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(detailItem)
        
        let copyTarget = MenuItemActionTarget {
            let targets = self.selectedItemIds.contains(item.id) ? self.displayItems.filter { self.selectedItemIds.contains($0.id) } : [item]
            let joinedContent = targets.map { $0.content }.joined(separator: "\n")
            let now = Date()
            for (idx, target) in targets.reversed().enumerated() {
                target.timestamp = now.addingTimeInterval(Double(idx) * 0.001)
            }
            try? self.modelContext.save()
            self.clipboardManager.copyToClipboard(content: joinedContent, recordInDatabase: false)
            NotificationCenter.default.post(name: .closeUI, object: nil)
        }
        let copyItem = NSMenuItem(title: "Copy", action: #selector(MenuItemActionTarget.execute), keyEquivalent: "")
        copyItem.target = copyTarget
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        objc_setAssociatedObject(copyItem, &actionTargetKey, copyTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(copyItem)
        
        let shareTarget = MenuItemActionTarget {
            let targets = self.selectedItemIds.contains(item.id) ? self.displayItems.filter { self.selectedItemIds.contains($0.id) } : [item]
            let joinedContent = targets.map { $0.content }.joined(separator: "\n")
            let picker = NSSharingServicePicker(items: [joinedContent])
            
            if let window = NSApp.keyWindow, let contentView = window.contentView {
                let mouseLocation = window.mouseLocationOutsideOfEventStream
                let dummyView = NSView(frame: NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 1))
                dummyView.focusRingType = .none
                contentView.addSubview(dummyView)
                
                let delegate = ShareDelegate { _ in
                    dummyView.removeFromSuperview()
                }
                
                objc_setAssociatedObject(picker, &shareDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                picker.delegate = delegate
                
                picker.show(relativeTo: dummyView.bounds, of: dummyView, preferredEdge: .minY)
            }
        }
        let shareItem = NSMenuItem(title: "Share", action: #selector(MenuItemActionTarget.execute), keyEquivalent: "")
        shareItem.target = shareTarget
        shareItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        objc_setAssociatedObject(shareItem, &actionTargetKey, shareTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(shareItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let targets = self.selectedItemIds.contains(item.id) ? self.displayItems.filter { self.selectedItemIds.contains($0.id) } : [item]
        let allPinned = targets.allSatisfy { $0.isPinned }
        let pinTarget = MenuItemActionTarget {
            withAnimation {
                for target in targets {
                    target.isPinned = !allPinned
                }
                try? self.modelContext.save()
            }
        }
        let pinItem = NSMenuItem(title: allPinned ? "Unpin" : "Pin", action: #selector(MenuItemActionTarget.execute), keyEquivalent: "")
        pinItem.target = pinTarget
        pinItem.image = NSImage(systemSymbolName: allPinned ? "pin.slash" : "pin", accessibilityDescription: nil)
        objc_setAssociatedObject(pinItem, &actionTargetKey, pinTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(pinItem)
        
        let allFavorite = targets.allSatisfy { $0.isFavorite }
        let favoriteTarget = MenuItemActionTarget {
            withAnimation {
                for target in targets {
                    target.isFavorite = !allFavorite
                }
                try? self.modelContext.save()
            }
        }
        let favoriteItem = NSMenuItem(title: allFavorite ? "Unfavorite" : "Favorite", action: #selector(MenuItemActionTarget.execute), keyEquivalent: "")
        favoriteItem.target = favoriteTarget
        favoriteItem.image = NSImage(systemSymbolName: allFavorite ? "star.slash" : "star", accessibilityDescription: nil)
        objc_setAssociatedObject(favoriteItem, &actionTargetKey, favoriteTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(favoriteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteTarget = MenuItemActionTarget {
            let targetsToDelete = self.selectedItemIds.contains(item.id) ? Array(self.selectedItemIds) : [item.id]
            let currentItems = self.displayItems
            let nextItem: ClipboardItem? = {
                let targetIndices = targetsToDelete.compactMap { targetId in
                    currentItems.firstIndex(where: { $0.id == targetId })
                }
                guard let maxIndex = targetIndices.max() else { return nil }
                if maxIndex + 1 < currentItems.count {
                    return currentItems[maxIndex + 1]
                } else {
                    let minIndex = targetIndices.min() ?? 0
                    if minIndex > 0 {
                        return currentItems[minIndex - 1]
                    }
                }
                return nil
            }()
            withAnimation {
                for targetId in targetsToDelete {
                    self.deletedItemIds.insert(targetId)
                    if let targetItem = currentItems.first(where: { $0.id == targetId }) {
                        self.clipboardManager.delete(item: targetItem)
                    }
                    self.searchResults.removeAll { $0.id == targetId }
                    self.selectedItemIds.remove(targetId)
                }
                self.isSelectionFromMouse = false
                self.selectedItemId = nextItem?.id
                if let nextId = nextItem?.id {
                    self.selectedItemIds = [nextId]
                } else {
                    self.selectedItemIds = []
                    self.showingDetail = false
                }
            }
        }
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(MenuItemActionTarget.execute), keyEquivalent: "")
        deleteItem.target = deleteTarget
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        objc_setAssociatedObject(deleteItem, &actionTargetKey, deleteTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(deleteItem)
        
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    private func openSettings() {
        presentSettingsWindow(manager: clipboardManager, importManager: importManager, container: modelContext.container, closeUIAfterOpen: true)
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
            if deletedItemIds.contains(item.id) { return false }
            if item.content.localizedCaseInsensitiveContains(query) { return true }
            
            let itemDate = item.timestamp
            
            if let qM = qMonth, let qD = qDay {
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
        aiSearchError = nil
        print("[AI Search] Starting search for: \(searchQuery) in mode: \(aiSearchMode)")
        Task {
            do {
                let intent: GeminiService.SearchIntent
                if aiSearchMode == "local" {
                    let localIntent = try await ollamaService.parseSearchIntent(query: searchQuery, history: history, baseURL: ollamaUrl, modelName: ollamaModel, searchDepth: semanticSearchDepth)
                    intent = GeminiService.SearchIntent(textQuery: localIntent.textQuery, startDate: localIntent.startDate, endDate: localIntent.endDate, semanticMatchIds: localIntent.semanticMatchIds)
                } else {
                    intent = try await geminiService.parseSearchIntent(query: searchQuery, history: history, apiKey: apiKey, modelName: selectedModel, searchDepth: semanticSearchDepth)
                }
                print("[AI Search] Received Intent: \(intent)")
                
                let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("SmartClipboard_ai_debug.log")
                let logContent = "--- SEARCH DEBUG ---\nTime: \(Date())\nQuery: \(searchQuery)\nIntent: \(intent)\n"
                if let data = logContent.data(using: .utf8) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        try? handle.seekToEnd()
                        handle.write(data)
                        try? handle.close()
                    } else {
                        try? logContent.write(to: logURL, atomically: true, encoding: .utf8)
                    }
                }
                
                await MainActor.run {
                    var filtered = self.history
                    if let ids = intent.semanticMatchIds, !ids.isEmpty {
                        let set = Set(ids); filtered = filtered.filter { set.contains($0.id) }
                        print("[AI Search] Found \(filtered.count) semantic matches")
                    } else {
                        if let s = intent.startDate, let e = intent.endDate { 
                            filtered = filtered.filter { $0.timestamp >= s && $0.timestamp <= e }
                            print("[AI Search] Filtered by date, found \(filtered.count) items")
                        }
                        if let t = intent.textQuery, !t.isEmpty { 
                            filtered = filtered.filter { $0.content.localizedCaseInsensitiveContains(t) }
                            print("[AI Search] Filtered by text query '\(t)', found \(filtered.count) items")
                        }
                    }
                    self.searchResults = filtered
                    self.pageLimit = 1
                    self.isSelectionFromMouse = false
                    self.selectedItemId = filtered.first?.id
                    if let firstId = filtered.first?.id {
                        self.selectedItemIds = [firstId]
                    } else {
                        self.selectedItemIds = []
                    }
                    self.isSearching = false
                }
            } catch {
                let errMsg = error.localizedDescription
                print("[AI Search] Error: \(errMsg)")
                
                let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("SmartClipboard_ai_debug.log")
                let logContent = "--- SEARCH ERROR ---\nTime: \(Date())\nQuery: \(searchQuery)\nError: \(error)\n"
                if let data = logContent.data(using: .utf8) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        try? handle.seekToEnd()
                        handle.write(data)
                        try? handle.close()
                    } else {
                        try? logContent.write(to: logURL, atomically: true, encoding: .utf8)
                    }
                }
                
                await MainActor.run {
                    let userMsg: String
                    if errMsg.contains("503") || errMsg.contains("high demand") || errMsg.contains("UNAVAILABLE") {
                        userMsg = "⚠️ Local model or cloud service is overloaded/unavailable."
                    } else if errMsg.contains("401") || errMsg.contains("API key") {
                        userMsg = "⚠️ Invalid API key. Check Settings."
                    } else if errMsg.contains("connection") || errMsg.contains("connect") || errMsg.contains("local") {
                        userMsg = "⚠️ Could not connect to local Ollama server."
                    } else {
                        userMsg = "⚠️ AI search failed. Try again."
                    }
                    self.aiSearchError = userMsg
                    self.isSearching = false
                }
            }
        }
    }
    
    private func triggerShare() {
        guard let item = selectedItem else { return }
        isSharingPickerOpen = true
        let picker = NSSharingServicePicker(items: [item.content])
        
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let xPos = contentView.bounds.width - 26
            let yPos = contentView.isFlipped ? 32 : (contentView.bounds.height - 32)
            let dummyView = NSView(frame: NSRect(x: xPos, y: yPos, width: 1, height: 1))
            dummyView.focusRingType = .none
            contentView.addSubview(dummyView)
            
            let delegate = ShareDelegate { service in
                dummyView.removeFromSuperview()
                isSharingPickerOpen = false
                if service != nil {
                    clipboardManager.onPaste?()
                }
            }
            
            objc_setAssociatedObject(picker, &shareDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            picker.delegate = delegate
            
            picker.show(relativeTo: dummyView.bounds, of: dummyView, preferredEdge: .minY)
        }
    }
    
    private var accessibilityWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))
            
            Text("Accessibility Permission Required")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.8))
            
            Spacer()
            
            Button {
                clipboardManager.requestAccessibilityPermission()
            } label: {
                Text("Enable")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .overlay(
            Divider().opacity(0.3),
            alignment: .bottom
        )
    }
    
    @ViewBuilder
    private var headerViewArea: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(isSearchFocused ? .primary : .secondary)
                    .font(.system(size: 13, weight: .medium))
                
                TextField("Search or Ask...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .accentColor(.secondary)
                    .onChange(of: searchQuery) { _, newValue in
                        if newValue.count > 2000 {
                            searchQuery = String(newValue.prefix(2000))
                        }
                        pageLimit = 1
                        performLocalSearch()
                        isSelectionFromMouse = false
                        let currentSnippets = matchingWorkflows
                        if !currentSnippets.isEmpty {
                            selectedWorkflowId = currentSnippets.first?.id
                            selectedItemId = nil
                            selectedItemIds = []
                        } else if let firstId = displayItems.first?.id {
                            selectedWorkflowId = nil
                            selectedItemId = firstId
                            selectedItemIds = [firstId]
                        } else {
                            selectedWorkflowId = nil
                            selectedItemId = nil
                            selectedItemIds = []
                        }
                    }
                    .onSubmit {
                        if let wfId = selectedWorkflowId,
                           let snippet = matchingWorkflows.first(where: { $0.id == wfId }) {
                            clipboardManager.paste(content: snippet.content)
                        } else if let id = selectedItemId, let item = displayItems.first(where: { $0.id == id }) {
                            clipboardManager.paste(item: item)
                        } else if let first = displayItems.first {
                            clipboardManager.paste(item: first)
                        }
                    }
                
                if isSearching {
                    ProgressView().scaleEffect(0.4).frame(width: 16, height: 16)
                } else if !searchQuery.isEmpty {
                    SparklesButton(
                        action: performAISearch,
                        isDisabled: apiKey.isEmpty,
                        tooltip: apiKey.isEmpty ? "API key required for AI Search (Configure in Settings)" : "Ask Siri AI Search"
                    )
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(isSearchFocused ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(isSearchFocused ? 0.12 : 0.06), lineWidth: 0.5)
            )
            
            if isQuickSelectActive {
                HStack(spacing: 4) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Release key to paste")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            
            if clipboardManager.incognitoMode {
                IncognitoIcon()
                    .transition(.scale.combined(with: .opacity))
            }
            
            HoverIconHelper(systemName: "gearshape", action: openSettings, tooltip: "Settings")
                .padding(.trailing, 1)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.top, 14) 
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var mainListContentArea: some View {
        if displayItems.isEmpty && matchingWorkflows.isEmpty {
            emptyStateView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        Color.clear
                            .frame(height: 0)
                            .id("list_top_anchor")

                        if isQuickSelectActive && isDismissSelected {
                            DismissRow(
                                isSelected: isDismissSelected,
                                onTap: {
                                    isQuickSelectActive = false
                                    isDismissSelected = false
                                    NotificationCenter.default.post(name: .closeUI, object: nil)
                                },
                                onHover: { hovering in
                                    if hovering && isQuickSelectActive {
                                        isSelectionFromMouse = true
                                        isDismissSelected = true
                                        selectedWorkflowId = nil
                                        selectedItemId = nil
                                        selectedItemIds = []
                                    }
                                }
                            )
                            .id("dismiss_row_id")
                            .padding(.horizontal, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        workflowSectionView

                        let now = Date()
                        let calendar = Calendar.current
                        let todayStart = calendar.startOfDay(for: now)
                        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

                        let snippetsCount = matchingWorkflows.count
                        ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                            let isSelected = !isDismissSelected && selectedWorkflowId == nil && selectedItemIds.contains(item.id)
                            let badgeIndex = getBadgeIndex(index: index)
                            ClipboardRow(
                                item: item,
                                index: index,
                                isSelected: isSelected,
                                timestamp: formatTimestamp(item.timestamp, todayStart: todayStart, tomorrowStart: tomorrowStart, yesterdayStart: yesterdayStart),
                                badgeIndex: badgeIndex,
                                onRowTap: {
                                    clearNavigationFallbacks()
                                    isDismissSelected = false
                                    let modifiers = NSEvent.modifierFlags
                                    if !modifiers.contains(.shift) && !modifiers.contains(.command) {
                                        isSelectionFromMouse = true
                                        selectedItemIds = [item.id]
                                        selectedItemId = item.id
                                        clipboardManager.paste(item: item)
                                    }
                                },
                                onLeftClickWithModifiers: { modifiers in
                                    isDismissSelected = false
                                    isSelectionFromMouse = true
                                    handleRowClick(itemId: item.id, modifiers: modifiers)
                                },
                                onRightClick: { modifiers in
                                    isDismissSelected = false
                                    isSelectionFromMouse = true
                                    handleRowRightClick(itemId: item.id, modifiers: modifiers)
                                    showNativeContextMenu(for: item)
                                },
                                onChevronTap: {
                                    isDismissSelected = false
                                    isSelectionFromMouse = true
                                    selectedItemId = item.id
                                    selectedItemIds = [item.id]
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        showingDetail = true
                                    }
                                },
                                onHover: { hovering in
                                    if hovering && isQuickSelectActive {
                                        isSelectionFromMouse = true
                                        isDismissSelected = false
                                        selectedWorkflowId = nil
                                        selectedItemId = item.id
                                        selectedItemIds = [item.id]
                                    }
                                },
                                dragContentProvider: {
                                    if selectedItemIds.contains(item.id) && selectedItemIds.count > 1 {
                                        let selectedItemsInOrder = displayItems.filter { selectedItemIds.contains($0.id) }
                                        let joinedContent = selectedItemsInOrder.map { $0.content }.joined(separator: "\n")
                                        return DragSessionInfo(
                                            content: joinedContent,
                                            previewTitle: item.content,
                                            itemCount: selectedItemsInOrder.count
                                        )
                                    } else {
                                        return DragSessionInfo(
                                            content: item.content,
                                            previewTitle: item.content,
                                            itemCount: 1
                                        )
                                    }
                                }
                            )
                            .tag(item.id)
                            .padding(.horizontal, 4)
                            .background(RowBackground(isSelected: isSelected))
                        }
                        
                        if allFilteredItems.count > pageLimit * pageSize {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                Spacer()
                            }
                            .frame(height: 44)
                            .onAppear {
                                pageLimit += 1
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                }
                .onChange(of: scrollToTopTrigger) { _, _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo("list_top_anchor", anchor: .top)
                        }
                    }
                }
                .onChange(of: isDismissSelected) { _, isDismiss in
                    if isDismiss && !isSelectionFromMouse {
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo("dismiss_row_id", anchor: .top)
                            }
                        }
                    }
                }
                .onChange(of: selectedWorkflowId) { _, newValue in
                    if let id = newValue, !isSelectionFromMouse {
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo(id, anchor: nil)
                            }
                        }
                    }
                }
                .onChange(of: selectedItemId) { _, newValue in
                    if let id = newValue, !isSelectionFromMouse {
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo(id, anchor: nil)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var workflowSectionView: some View {
        if !matchingWorkflows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(matchingWorkflows.enumerated()), id: \.element.id) { index, snippet in
                    let isSelected = !isDismissSelected && selectedWorkflowId == snippet.id
                    WorkflowRow(
                        snippet: snippet,
                        isSelected: isSelected,
                        badgeIndex: nil,
                        onTap: {
                            isDismissSelected = false
                            clipboardManager.paste(content: snippet.content)
                        },
                        onChevronTap: {
                            isDismissSelected = false
                            selectedWorkflowId = snippet.id
                            detailSnippet = snippet
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingSnippetDetail = true
                            }
                        },
                        onHover: { hovering in
                            if hovering && isQuickSelectActive {
                                isSelectionFromMouse = true
                                isDismissSelected = false
                                selectedWorkflowId = snippet.id
                                selectedItemId = nil
                                selectedItemIds = []
                            }
                        },
                        dragContentProvider: {
                            return DragSessionInfo(
                                content: snippet.content,
                                previewTitle: snippet.title,
                                itemCount: 1
                            )
                        }
                    )
                    .padding(.horizontal, 4)
                    .background(RowBackground(isSelected: isSelected))
                }
                
                // Subtle divider between snippets and clipboard items
                Divider()
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            if searchQuery.isEmpty {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.03))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.03))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            
            VStack(spacing: 6) {
                if let errorMsg = aiSearchError {
                    Text(errorMsg)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 24)
                } else {
                    Text(searchQuery.isEmpty ? "Clipboard is empty" : (isSearching ? "Searching with AI..." : "No matches found"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.8))
                    
                    Text(searchQuery.isEmpty ? "Copy some text to get started." : (isSearching ? "Please wait a moment." : "Try adjusting your keywords or filters."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            
            if searchQuery.isEmpty {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString("Hello, SmartClipboard! 👋", forType: .string)
                } label: {
                    Label("Copy Sample Text", systemImage: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)
                .padding(.top, 8)
                .accessibilityLabel("Copy Sample Text")
                .help("Copy text to populate clipboard")
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Window Accessor
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        DispatchQueue.main.async {
            self.onWindow(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.onWindow(nsView.window)
        }
    }
}

// MARK: - VisualEffectView
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

// MARK: - GlassEffectView
@available(macOS 26.0, *)
struct GlassEffectView: NSViewRepresentable {
    var style: NSGlassEffectView.Style = .regular
    var tintColor: NSColor? = nil
    var cornerRadius: CGFloat = 0
    
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = style
        if cornerRadius > 0 {
            view.cornerRadius = cornerRadius
        }
        view.tintColor = tintColor
        return view
    }
    
    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.style = style
        if cornerRadius > 0 {
            nsView.cornerRadius = cornerRadius
        }
        nsView.tintColor = tintColor
    }
}

// MARK: - DismissRow
struct DismissRow: View {
    let isSelected: Bool
    let onTap: () -> Void
    var onHover: ((Bool) -> Void)? = nil
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.red.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.red.opacity(0.4), lineWidth: 0.5)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? .red : .secondary)
                }
                .frame(width: 18, height: 18)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dismiss")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .primary : .primary.opacity(0.9))
                    
                    Text("Release key to close without pasting")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 0)
                
                Text("Esc")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isHovered ? Color.primary.opacity(0.06) : Color.clear, lineWidth: 0.5)
                        )
                }
            }
        )
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
            onHover?(hovering)
        }
    }
}

// MARK: - WorkflowRow
struct WorkflowRow: View {
    let snippet: WorkflowSnippet
    let isSelected: Bool
    var badgeIndex: Int? = nil
    let onTap: () -> Void
    let onChevronTap: () -> Void
    var onHover: ((Bool) -> Void)? = nil
    var dragContentProvider: (() -> DragSessionInfo?)? = nil
    
    @State private var isChevronHovered = false
    
    var body: some View {
        // Same outer structure as ClipboardRow
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                if let badgeIndex = badgeIndex {
                    KeycapBadge(index: badgeIndex, isSelected: isSelected)
                } else {
                    Spacer().frame(width: 18, height: 18)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    // Trigger badge on top line (like timestamp row)
                    Text(snippet.trigger)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    // Title as the main content line
                    Text(snippet.title)
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(2)
                        .lineSpacing(2.5)
                        .foregroundColor(.primary.opacity(0.9))
                }
                
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay(
                MouseDetectorView(
                    isSelected: isSelected,
                    onLeftClick: { _ in },
                    onRightClick: { _ in },
                    onTap: { onTap() },
                    onHover: { hovering in
                        onHover?(hovering)
                    },
                    dragContentProvider: dragContentProvider
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            
            // Chevron — identical to ClipboardRow
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isChevronHovered ? .primary : .secondary.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isChevronHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .contentShape(Circle())
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    withAnimation(.easeOut(duration: 0.12)) { isChevronHovered = hovering }
                }
                .onTapGesture { onChevronTap() }
                .padding(.trailing, 2)
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .onHover { hovering in
            onHover?(hovering)
        }
    }
}


// MARK: - TwoTonePinIcon
struct TwoTonePinIcon: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.primary.opacity(0.6))
            .overlay(
                GeometryReader { geo in
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.red)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .mask(
                            VStack(spacing: 0) {
                                Rectangle()
                                    .frame(height: geo.size.height * 0.68)
                                Spacer(minLength: 0)
                            }
                        )
                }
            )
            .offset(y: 1)
            .help("Pinned")
    }
}

// MARK: - ClipboardRow
struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let timestamp: String
    var badgeIndex: Int? = nil
    let onRowTap: () -> Void
    let onLeftClickWithModifiers: (NSEvent.ModifierFlags) -> Void
    let onRightClick: (NSEvent.ModifierFlags) -> Void
    let onChevronTap: () -> Void
    var onHover: ((Bool) -> Void)? = nil
    var dragContentProvider: (() -> DragSessionInfo?)? = nil
    
    @State private var isChevronHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Main left/middle content
            HStack(spacing: 12) {
                if let badgeIndex = badgeIndex {
                    KeycapBadge(index: badgeIndex, isSelected: isSelected)
                } else {
                    Spacer().frame(width: 18, height: 18)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if item.isPinned {
                            TwoTonePinIcon()
                        }
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.yellow)
                                .offset(y: -1)
                                .help("Favorite")
                        }
                        
                        Text(timestamp)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if item.isIncognito {
                            IncognitoGlyph()
                                .frame(width: 10, height: 10)
                                .foregroundColor(.secondary)
                                .help("Copied in Incognito Mode")
                        }
                    }
                    
                    Text(item.content)
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(2)
                        .lineSpacing(2.5)
                        .foregroundColor(.primary.opacity(0.9))
                }
                
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay(
                MouseDetectorView(
                    isSelected: isSelected,
                    onLeftClick: { modifiers in
                        onLeftClickWithModifiers(modifiers)
                    },
                    onRightClick: { modifiers in
                        onRightClick(modifiers)
                    },
                    onTap: {
                        onRowTap()
                    },
                    onHover: { hovering in
                        onHover?(hovering)
                    },
                    dragContentProvider: dragContentProvider
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            
            // Chevron button (right side, fully outside overlay and row tap gestures)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isChevronHovered ? .primary : .secondary.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isChevronHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .contentShape(Circle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                    withAnimation(.easeOut(duration: 0.12)) {
                        isChevronHovered = hovering
                    }
                }
                .onTapGesture {
                    onChevronTap()
                }
                .padding(.trailing, 2)
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .onHover { hovering in
            onHover?(hovering)
        }
    }
}

// MARK: - ClipboardDetailView
struct ClipboardDetailView: View {
    @EnvironmentObject private var clipboardManager: ClipboardManager
    let item: ClipboardItem
    @Binding var isSharingPickerOpen: Bool
    let isInPopover: Bool
    let onBack: () -> Void
    @AppStorage("themeStyle") private var themeStyle = "darkGlass"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackButton(action: onBack)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("Clipboard Detail")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.8))
                    
                    if item.isIncognito {
                        IncognitoGlyph()
                            .frame(width: 11, height: 11)
                            .foregroundColor(.secondary)
                            .help("Copied in Incognito Mode")
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    ShareButton(
                        content: item.content,
                        onShow: { isSharingPickerOpen = true },
                        onDismiss: { service in
                            isSharingPickerOpen = false
                            if service != nil {
                                clipboardManager.onPaste?()
                            }
                        }
                    )
                    .frame(width: 28, height: 28)
                    .help("Share Item")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .textSelection(.disabled)
            
            Divider().opacity(0.3)
            
            ScrollView {
                Text(item.content)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(4)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, isInPopover ? 10 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme((themeStyle == "dark" || themeStyle == "darkGlass") ? .dark : (themeStyle == "light" ? .light : nil))
        .background(
            ZStack {
                if themeStyle == "dark" {
                    Color(red: 0.118, green: 0.118, blue: 0.118)
                } else if themeStyle == "light" {
                    Color(red: 0.96, green: 0.96, blue: 0.96)
                } else if themeStyle == "darkGlass" {
                    if #available(macOS 26.0, *) {
                        GlassEffectView(
                            style: .clear,
                            tintColor: NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.89),
                            cornerRadius: 16
                        )
                    } else {
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 16)
                        Color.black.opacity(0.4)
                    }
                    
                    // macOS Golden Gate liquid glass light-reflection overlay
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.clear,
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .cornerRadius(16)
                } else {
                    if #available(macOS 26.0, *) {
                        GlassEffectView(style: .regular, cornerRadius: 16)
                    } else {
                        VisualEffectView(material: .popover, blendingMode: .behindWindow, cornerRadius: 16)
                    }
                    
                    // macOS Golden Gate liquid glass light-reflection overlay
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.clear,
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .cornerRadius(16)
                }
            }
            .clipShape(PopoverBubbleShape(showArrow: isInPopover))
            .overlay(
                PopoverBubbleShape(showArrow: isInPopover)
                    .stroke(
                        themeStyle == "light" ? Color.black.opacity(0.03) : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - SnippetPencilButton
struct SnippetPencilButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .help("Edit Snippet")
    }
}

// MARK: - SnippetDetailView
struct SnippetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var clipboardManager: ClipboardManager
    let snippet: WorkflowSnippet
    let isInPopover: Bool
    let onBack: () -> Void
    @AppStorage("themeStyle") private var themeStyle = "darkGlass"
    
    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editTrigger = ""
    @State private var editContent = ""
    @State private var isSaved = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar — mirrors ClipboardDetailView
            HStack(spacing: 12) {
                BackButton(action: onBack)
                
                Spacer()
                
                Text(isEditing ? "Edit Snippet" : "Snippet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.8))
                
                Spacer()
                
                HStack(spacing: 8) {
                    if isEditing {
                        Button("Done") {
                            saveEdits()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(editTrigger.trimmingCharacters(in: .whitespaces).isEmpty || editContent.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .textSelection(.disabled)
            
            Divider().opacity(0.3)
            
            if isEditing {
                // Edit mode — inline edit fields
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Trigger
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Slash Command")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            TextField("/trigger", text: $editTrigger)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }
                        
                        // Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            TextField("Name", text: $editTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }
                        
                        // Content
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Content")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            ZStack(alignment: .topLeading) {
                                if editContent.isEmpty {
                                    Text("Content...")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary.opacity(0.5))
                                        .padding(.horizontal, 10)
                                        .padding(.top, 10)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $editContent)
                                    .font(.system(size: 12.5))
                                    .lineSpacing(3)
                                    .frame(minHeight: 160)
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                            }
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        
                        if isSaved {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Saved")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Read mode — mirrors ClipboardDetailView layout
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Metadata row: trigger pill + title + edit button
                        HStack(spacing: 8) {
                            Text(snippet.trigger)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.primary.opacity(0.07))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                        )
                                )

                            Text(snippet.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.85))
                                .lineLimit(1)

                            Spacer()

                            SnippetPencilButton(action: enterEditing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                        Divider().opacity(0.3)

                        // Full snippet content — same treatment as clipboard detail
                        Text(snippet.content)
                            .font(.system(size: 12.5))
                            .lineSpacing(4)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .foregroundColor(.primary.opacity(0.85))
                    }
                }
            }
        }
        .padding(.top, isInPopover ? 10 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme((themeStyle == "dark" || themeStyle == "darkGlass") ? .dark : (themeStyle == "light" ? .light : nil))
        .background(
            ZStack {
                if themeStyle == "dark" {
                    Color(red: 0.118, green: 0.118, blue: 0.118)
                } else if themeStyle == "light" {
                    Color(red: 0.96, green: 0.96, blue: 0.96)
                } else if themeStyle == "darkGlass" {
                    if #available(macOS 26.0, *) {
                        GlassEffectView(
                            style: .clear,
                            tintColor: NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.89),
                            cornerRadius: 16
                        )
                    } else {
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 16)
                        Color.black.opacity(0.4)
                    }
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.clear,
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .cornerRadius(16)
                } else {
                    if #available(macOS 26.0, *) {
                        GlassEffectView(style: .regular, cornerRadius: 16)
                    } else {
                        VisualEffectView(material: .popover, blendingMode: .behindWindow, cornerRadius: 16)
                    }
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.clear,
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .cornerRadius(16)
                }
            }
            .clipShape(PopoverBubbleShape(showArrow: isInPopover))
            .overlay(
                PopoverBubbleShape(showArrow: isInPopover)
                    .stroke(
                        themeStyle == "light" ? Color.black.opacity(0.03) : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
            )
            .ignoresSafeArea()
        )
    }
    
    private func enterEditing() {
        editTitle = snippet.title
        editTrigger = snippet.trigger
        editContent = snippet.content
        isSaved = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
    }
    
    private func saveEdits() {
        guard !editTrigger.trimmingCharacters(in: .whitespaces).isEmpty,
              !editContent.isEmpty else { return }
        snippet.title = editTitle.isEmpty ? editTrigger : editTitle
        let formatted = editTrigger.trimmingCharacters(in: .whitespaces)
        snippet.trigger = formatted.hasPrefix("/") ? formatted : "/\(formatted)"
        snippet.content = editContent
        try? modelContext.save()
        withAnimation {
            isSaved = true
            isEditing = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isSaved = false
        }
    }
}


// MARK: - ShareButton
struct ShareButton: View {
    let content: String
    let onShow: () -> Void
    let onDismiss: (NSSharingService?) -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button {
            onShow()
            let picker = NSSharingServicePicker(items: [content])
            
            if let window = NSApp.keyWindow, let contentView = window.contentView {
                let xPos = contentView.bounds.width - 26
                let yPos = contentView.isFlipped ? 32 : (contentView.bounds.height - 32)
                let dummyView = NSView(frame: NSRect(x: xPos, y: yPos, width: 1, height: 1))
                dummyView.focusRingType = .none
                contentView.addSubview(dummyView)
                
                let delegate = ShareDelegate { service in
                    dummyView.removeFromSuperview()
                    onDismiss(service)
                }
                
                objc_setAssociatedObject(picker, &shareDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                picker.delegate = delegate
                
                picker.show(relativeTo: dummyView.bounds, of: dummyView, preferredEdge: .minY)
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - IncognitoIcon Shapes & Glyphs
struct HatCrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.24, y: h * 0.45))
        path.addCurve(to: CGPoint(x: w * 0.32, y: h * 0.10),
                      control1: CGPoint(x: w * 0.24, y: h * 0.25),
                      control2: CGPoint(x: w * 0.28, y: h * 0.15))
        path.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.20),
                      control1: CGPoint(x: w * 0.38, y: h * 0.05),
                      control2: CGPoint(x: w * 0.44, y: h * 0.20))
        path.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.10),
                      control1: CGPoint(x: w * 0.56, y: h * 0.20),
                      control2: CGPoint(x: w * 0.62, y: h * 0.05))
        path.addCurve(to: CGPoint(x: w * 0.76, y: h * 0.45),
                      control1: CGPoint(x: w * 0.72, y: h * 0.15),
                      control2: CGPoint(x: w * 0.76, y: h * 0.25))
        path.closeSubpath()
        return path
    }
}

struct HatBrimShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.10, y: h * 0.45))
        path.addQuadCurve(to: CGPoint(x: w * 0.90, y: h * 0.45),
                          control: CGPoint(x: w * 0.50, y: h * 0.58))
        path.addQuadCurve(to: CGPoint(x: w * 0.86, y: h * 0.38),
                          control: CGPoint(x: w * 0.88, y: h * 0.41))
        path.addQuadCurve(to: CGPoint(x: w * 0.14, y: h * 0.38),
                          control: CGPoint(x: w * 0.50, y: h * 0.48))
        path.addQuadCurve(to: CGPoint(x: w * 0.10, y: h * 0.45),
                          control: CGPoint(x: w * 0.12, y: h * 0.41))
        path.closeSubpath()
        return path
    }
}

struct GlassesView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lensY = h * 0.66
            
            ZStack {
                // Left Lens
                Circle()
                    .stroke(lineWidth: w * 0.08)
                    .frame(width: w * 0.24, height: w * 0.24)
                    .position(x: w * 0.35, y: lensY)
                
                // Right Lens
                Circle()
                    .stroke(lineWidth: w * 0.08)
                    .frame(width: w * 0.24, height: w * 0.24)
                    .position(x: w * 0.65, y: lensY)
                
                // Bridge (connecting line)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.46, y: lensY))
                    path.addQuadCurve(to: CGPoint(x: w * 0.54, y: lensY),
                                      control: CGPoint(x: w * 0.50, y: lensY - w * 0.03))
                }
                .stroke(lineWidth: w * 0.08)
            }
        }
    }
}

struct IncognitoGlyph: View {
    var body: some View {
        ZStack {
            HatCrownShape()
                .fill()
            
            HatBrimShape()
                .fill()
            
            GlassesView()
        }
        .aspectRatio(1.0, contentMode: .fit)
    }
}

// MARK: - IncognitoIcon
struct IncognitoIcon: View {
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                clipboardManager.incognitoMode = false
            }
        }) {
            IncognitoGlyph()
                .frame(width: 14, height: 14)
                .foregroundColor(isHovered ? .secondary : .primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.03) : Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(isHovered ? 0.08 : 0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .help("Incognito Mode Active (Click to disable)")
    }
}

// MARK: - DragSessionInfo
struct DragSessionInfo {
    let content: String
    let previewTitle: String?
    let itemCount: Int
}

// MARK: - MouseDetectorView
struct MouseDetectorView: NSViewRepresentable {
    let isSelected: Bool
    let onLeftClick: (NSEvent.ModifierFlags) -> Void
    let onRightClick: (NSEvent.ModifierFlags) -> Void
    let onTap: () -> Void
    var onHover: ((Bool) -> Void)? = nil
    var dragContentProvider: (() -> DragSessionInfo?)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = MouseDetectingNSView()
        view.isSelected = isSelected
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onTap = onTap
        view.onHover = onHover
        view.dragContentProvider = dragContentProvider
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? MouseDetectingNSView {
            view.isSelected = isSelected
            view.onLeftClick = onLeftClick
            view.onRightClick = onRightClick
            view.onTap = onTap
            view.onHover = onHover
            view.dragContentProvider = dragContentProvider
        }
    }
}

class MouseDetectingNSView: NSView, NSDraggingSource {
    var isSelected: Bool = false
    var onLeftClick: ((NSEvent.ModifierFlags) -> Void)?
    var onRightClick: ((NSEvent.ModifierFlags) -> Void)?
    var onTap: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var dragContentProvider: (() -> DragSessionInfo?)?
    
    private var trackingArea: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var mouseDownModifiers: NSEvent.ModifierFlags = []
    private var isDraggingSessionActive = false
    private var didDrag = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if self.bounds.contains(point) {
            return self
        }
        return nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        mouseDownModifiers = event.modifierFlags
        didDrag = false
        isDraggingSessionActive = false
        
        let hasShiftOrCmd = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
        if hasShiftOrCmd {
            onLeftClick?(event.modifierFlags)
        } else {
            if !isSelected {
                onLeftClick?(event.modifierFlags)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, !isDraggingSessionActive, let startPoint = mouseDownPoint else { return }
        let currentPoint = event.locationInWindow
        let distance = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)
        
        if distance >= 3.0 {
            didDrag = true
            isDraggingSessionActive = true
            startDragSession(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag && !isDraggingSessionActive else {
            didDrag = false
            mouseDownPoint = nil
            return
        }
        
        let hasShiftOrCmd = mouseDownModifiers.contains(.shift) || mouseDownModifiers.contains(.command)
        if !hasShiftOrCmd {
            if isSelected {
                onLeftClick?(mouseDownModifiers)
            }
            onTap?()
        }
        
        mouseDownPoint = nil
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event.modifierFlags)
    }

    private func startDragSession(with event: NSEvent) {
        guard let dragInfo = dragContentProvider?(), !dragInfo.content.isEmpty else {
            isDraggingSessionActive = false
            return
        }
        
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(dragInfo.content, forType: .string)
        
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        
        let previewImage = Self.createDragPreviewImage(
            title: dragInfo.previewTitle ?? dragInfo.content,
            count: dragInfo.itemCount
        )
        
        let mouseInView = convert(event.locationInWindow, from: nil)
        let imgSize = previewImage.size
        let frame = NSRect(
            x: mouseInView.x - 16,
            y: mouseInView.y - (imgSize.height / 2),
            width: imgSize.width,
            height: imgSize.height
        )
        
        draggingItem.setDraggingFrame(frame, contents: previewImage)
        
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingSessionActive = false
        didDrag = false
        mouseDownPoint = nil
    }

    static func createDragPreviewImage(title: String, count: Int) -> NSImage {
        let cleanText = title
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = cleanText.count > 45 ? String(cleanText.prefix(45)) + "…" : cleanText
        
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        
        let textSize = (displayText as NSString).size(withAttributes: textAttributes)
        let horizontalPadding: CGFloat = 12
        let iconWidth: CGFloat = 16
        let iconSpacing: CGFloat = 8
        let badgeExtraWidth: CGFloat = count > 1 ? 26 : 0
        
        let totalWidth = min(max(textSize.width + horizontalPadding * 2 + iconWidth + iconSpacing + badgeExtraWidth, 90), 280)
        let totalHeight: CGFloat = 32
        
        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { bounds in
            let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
            NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
            bgPath.fill()
            
            NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
            bgPath.lineWidth = 1
            bgPath.stroke()
            
            let iconRect = NSRect(x: horizontalPadding, y: (totalHeight - iconWidth) / 2, width: iconWidth, height: iconWidth)
            if let docIcon = NSImage(systemSymbolName: count > 1 ? "doc.on.doc.fill" : "doc.text.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                let tintedIcon = docIcon.withSymbolConfiguration(config)
                tintedIcon?.draw(in: iconRect)
            }
            
            let textX = horizontalPadding + iconWidth + iconSpacing
            let textMaxWidth = totalWidth - textX - horizontalPadding - badgeExtraWidth
            let textRect = NSRect(
                x: textX,
                y: (totalHeight - textSize.height) / 2,
                width: max(textMaxWidth, 10),
                height: textSize.height
            )
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail
            var attrs = textAttributes
            attrs[.paragraphStyle] = paragraphStyle
            
            (displayText as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            
            if count > 1 {
                let badgeText = "\(count)"
                let badgeFont = NSFont.systemFont(ofSize: 10, weight: .bold)
                let badgeTextAttrs: [NSAttributedString.Key: Any] = [
                    .font: badgeFont,
                    .foregroundColor: NSColor.white
                ]
                let badgeTextSize = (badgeText as NSString).size(withAttributes: badgeTextAttrs)
                let badgeWidth = max(badgeTextSize.width + 10, 20)
                let badgeHeight: CGFloat = 18
                let badgeRect = NSRect(
                    x: totalWidth - horizontalPadding - badgeWidth + 4,
                    y: (totalHeight - badgeHeight) / 2,
                    width: badgeWidth,
                    height: badgeHeight
                )
                
                let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 9, yRadius: 9)
                NSColor.systemBlue.setFill()
                badgePath.fill()
                
                let badgeTextDrawRect = NSRect(
                    x: badgeRect.minX + (badgeWidth - badgeTextSize.width) / 2,
                    y: badgeRect.minY + (badgeHeight - badgeTextSize.height) / 2,
                    width: badgeTextSize.width,
                    height: badgeTextSize.height
                )
                (badgeText as NSString).draw(in: badgeTextDrawRect, withAttributes: badgeTextAttrs)
            }
            
            return true
        }
        
        return image
    }
}

// MARK: - PopoverBubbleShape
struct PopoverBubbleShape: Shape {
    var arrowHeight: CGFloat = 10
    var arrowWidth: CGFloat = 24
    var cornerRadius: CGFloat = 16
    var showArrow: Bool
    
    func path(in rect: CGRect) -> Path {
        if !showArrow {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        }
        
        var path = Path()
        
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY + arrowHeight
        let maxY = rect.maxY
        
        let midX = rect.midX
        let arrowLeft = midX - arrowWidth / 2
        let arrowRight = midX + arrowWidth / 2
        
        // Start from top-left corner (after the radius)
        path.move(to: CGPoint(x: minX + cornerRadius, y: minY))
        
        // Go to left side of the arrow
        path.addLine(to: CGPoint(x: arrowLeft, y: minY))
        
        // Draw the gentle popover arrow using S-curves and a rounded cap
        let tipOffset: CGFloat = 2.2
        let tipHeightOffset: CGFloat = 1.3
        
        path.addCurve(
            to: CGPoint(x: midX - tipOffset, y: rect.minY + tipHeightOffset),
            control1: CGPoint(x: arrowLeft + 3.5, y: minY),
            control2: CGPoint(x: midX - 4.5, y: rect.minY + 2.5)
        )
        
        path.addQuadCurve(
            to: CGPoint(x: midX + tipOffset, y: rect.minY + tipHeightOffset),
            control: CGPoint(x: midX, y: rect.minY)
        )
        
        path.addCurve(
            to: CGPoint(x: arrowRight, y: minY),
            control1: CGPoint(x: midX + 4.5, y: rect.minY + 2.5),
            control2: CGPoint(x: arrowRight - 3.5, y: minY)
        )
        
        // Go to top-right corner before radius
        path.addLine(to: CGPoint(x: maxX - cornerRadius, y: minY))
        
        // Top-right corner arc
        path.addArc(
            center: CGPoint(x: maxX - cornerRadius, y: minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(radians: -Double.pi / 2),
            endAngle: Angle(radians: 0),
            clockwise: false
        )
        
        // Right side
        path.addLine(to: CGPoint(x: maxX, y: maxY - cornerRadius))
        
        // Bottom-right corner arc
        path.addArc(
            center: CGPoint(x: maxX - cornerRadius, y: maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(radians: 0),
            endAngle: Angle(radians: Double.pi / 2),
            clockwise: false
        )
        
        // Bottom side
        path.addLine(to: CGPoint(x: minX + cornerRadius, y: maxY))
        
        // Bottom-left corner arc
        path.addArc(
            center: CGPoint(x: minX + cornerRadius, y: maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(radians: Double.pi / 2),
            endAngle: Angle(radians: Double.pi),
            clockwise: false
        )
        
        // Left side
        path.addLine(to: CGPoint(x: minX, y: minY + cornerRadius))
        
        // Top-left corner arc
        path.addArc(
            center: CGPoint(x: minX + cornerRadius, y: minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(radians: Double.pi),
            endAngle: Angle(radians: -Double.pi / 2),
            clockwise: false
        )
        
        path.closeSubpath()
        return path
    }
}
