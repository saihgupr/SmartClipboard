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
    @State private var selectedItemIds: Set<UUID> = []
    @State private var showingDetail = false
    @State private var isSelectionFromMouse = false
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

    var displayItems: [ClipboardItem] {
        Array(allFilteredItems.prefix(pageLimit * pageSize))
    }

    var selectedItem: ClipboardItem? {
        displayItems.first { $0.id == selectedItemId }
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
                // macOS Golden Gate Spotlight Style AI Search Header
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
                                if let firstId = displayItems.first?.id {
                                    selectedItemId = firstId
                                    selectedItemIds = [firstId]
                                } else {
                                    selectedItemId = nil
                                    selectedItemIds = []
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
                
                if !clipboardManager.hasAccessibilityPermission {
                    accessibilityWarning
                }
                
                // Clipboard Items List
                if displayItems.isEmpty {
                    emptyStateView
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                let now = Date()
                                let calendar = Calendar.current
                                let todayStart = calendar.startOfDay(for: now)
                                let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                                let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

                                ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                                    let isSelected = selectedItemIds.contains(item.id)
                                    ClipboardRow(
                                        item: item,
                                        index: index,
                                        isSelected: isSelected,
                                        timestamp: formatTimestamp(item.timestamp, todayStart: todayStart, tomorrowStart: tomorrowStart, yesterdayStart: yesterdayStart),
                                        onRowTap: {
                                            clearNavigationFallbacks()
                                            let modifiers = NSEvent.modifierFlags
                                            if !modifiers.contains(.shift) && !modifiers.contains(.command) {
                                                isSelectionFromMouse = true
                                                selectedItemIds = [item.id]
                                                selectedItemId = item.id
                                                clipboardManager.paste(item: item)
                                            }
                                        },
                                        onLeftClickWithModifiers: { modifiers in
                                            isSelectionFromMouse = true
                                            handleRowClick(itemId: item.id, modifiers: modifiers)
                                        },
                                        onRightClick: { modifiers in
                                            isSelectionFromMouse = true
                                            handleRowRightClick(itemId: item.id, modifiers: modifiers)
                                            showNativeContextMenu(for: item)
                                        },
                                        onChevronTap: {
                                            isSelectionFromMouse = true
                                            selectedItemId = item.id
                                            selectedItemIds = [item.id]
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                showingDetail = true
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
                        .onChange(of: selectedItemId) { _, newValue in
                            if let id = newValue, !isSelectionFromMouse {
                                DispatchQueue.main.async {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        proxy.scrollTo(id)
                                    }
                                }
                            }
                        }
                    }
                }
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
            selectedItemId = displayItems.first?.id
            if let firstId = selectedItemId {
                selectedItemIds = [firstId]
            }
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiWillShow)) { notification in
            let targetIsPopover = notification.userInfo?["isInPopover"] as? Bool ?? false
            isShownAsPopover = targetIsPopover
            
            searchQuery = ""
            pageLimit = 1
            isSelectionFromMouse = false
            selectedItemId = history.first?.id
            if let firstId = selectedItemId {
                selectedItemIds = [firstId]
            } else {
                selectedItemIds = []
            }
            showingDetail = false
            leftArrowDismissedDetail = false
            isSharingPickerOpen = false
            
            removeKeyboardMonitor()
            setupKeyboardMonitor()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
    }

    @State private var keyboardMonitor: Any?

    private func navigateNextItem() {
        if let fallbackId = nextItemBeforeCopyId {
            selectedItemId = fallbackId
            selectedItemIds = [fallbackId]
            clearNavigationFallbacks()
            return
        }
        
        let items = displayItems
        guard !items.isEmpty else { return }
        if let currentId = selectedItemId,
           let idx = items.firstIndex(where: { $0.id == currentId }) {
            if idx < items.count - 1 {
                let nextId = items[idx + 1].id
                selectedItemId = nextId
                selectedItemIds = [nextId]
            } else if allFilteredItems.count > pageLimit * pageSize {
                withAnimation {
                    pageLimit += 1
                }
                DispatchQueue.main.async {
                    let newItems = displayItems
                    if idx + 1 < newItems.count {
                        let nextId = newItems[idx + 1].id
                        selectedItemId = nextId
                        selectedItemIds = [nextId]
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
            selectedItemId = fallbackId
            selectedItemIds = [fallbackId]
            clearNavigationFallbacks()
            return
        }
        
        let items = displayItems
        guard !items.isEmpty else { return }
        if let currentId = selectedItemId,
           let idx = items.firstIndex(where: { $0.id == currentId }) {
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
        if let idx = items.firstIndex(where: { $0.id == itemId }) {
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

            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command && event.keyCode == 8 {
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
                if showingDetail {
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
                if let id = selectedItemId,
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
            for target in targets {
                target.timestamp = Date()
            }
            try? modelContext.save()
            clipboardManager.copyToClipboard(content: joinedContent)
        }
        
        if action == "quickCopy" {
            let currentItems = displayItems
            let targetIndices = targets.compactMap { target in
                currentItems.firstIndex(where: { $0.id == target.id })
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
            let targetIndices = targets.compactMap { target in
                currentItems.firstIndex(where: { $0.id == target.id })
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
        guard let clickedIndex = items.firstIndex(where: { $0.id == itemId }) else { return }
        
        if modifiers.contains(.shift) {
            if let firstSelectedId = selectedItemId,
               let anchorIndex = items.firstIndex(where: { $0.id == firstSelectedId }) {
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
    let onRowTap: () -> Void
    let onLeftClickWithModifiers: (NSEvent.ModifierFlags) -> Void
    let onRightClick: (NSEvent.ModifierFlags) -> Void
    let onChevronTap: () -> Void
    
    @State private var isChevronHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Main left/middle content
            HStack(spacing: 12) {
                if index < 10 {
                    KeycapBadge(index: index, isSelected: isSelected)
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
                    onLeftClick: { modifiers in
                        onLeftClickWithModifiers(modifiers)
                    },
                    onRightClick: { modifiers in
                        onRightClick(modifiers)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            .onTapGesture {
                onRowTap()
            }
            
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
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
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

// MARK: - MouseDetectorView
struct MouseDetectorView: NSViewRepresentable {
    let onLeftClick: (NSEvent.ModifierFlags) -> Void
    let onRightClick: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MouseDetectingNSView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class MouseDetectingNSView: NSView {
    var onLeftClick: ((NSEvent.ModifierFlags) -> Void)?
    var onRightClick: ((NSEvent.ModifierFlags) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if self.bounds.contains(point) {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        onLeftClick?(event.modifierFlags)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event.modifierFlags)
        super.rightMouseDown(with: event)
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
