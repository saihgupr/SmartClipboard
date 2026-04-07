import AppKit
import Combine
import SwiftData
import SwiftUI

@Model
final class ClipboardItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var content: String
    var timestamp: Date
    
    init(id: UUID = UUID(), content: String, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }
}

@MainActor
class ClipboardManager: ObservableObject {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let modelContext: ModelContext
    
    /// Optional callback invoked when a paste operation is triggered from the UI.
    var onPaste: (() -> Void)?

    /// Tracks if the app has macOS Accessibility permissions required for simulated keystrokes (Cmd+V).
    @Published var hasAccessibilityPermission: Bool = AXIsProcessTrusted()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        lastChangeCount = pasteboard.changeCount
        startPolling()

        // Run an initial pruning of old records
        pruneOldRecords()

        // Install global hotkeys (Cmd+N and Option+N) that work from any app
        GlobalHotkeyManager.shared.onPasteItem = { [weak self] index in
            self?.pasteItem(at: index)
        }
        GlobalHotkeyManager.shared.onPasteMultiple = { [weak self] count in
            self?.pasteMultiple(count: count)
        }
        GlobalHotkeyManager.shared.install()

        // Check permissions immediately
        refreshAccessibilityPermission()
    }

    func startPolling() {
        // Check the clipboard and accessibility permissions every 1 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
                
                // If we don't have permission, keep checking so the warning can disappear automatically
                if self?.hasAccessibilityPermission == false {
                    self?.refreshAccessibilityPermission()
                }
            }
        }
    }

    func refreshAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        if hasAccessibilityPermission != trusted {
            hasAccessibilityPermission = trusted
        }
    }

    /// Triggers the macOS system prompt to request Accessibility permissions.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        refreshAccessibilityPermission()
    }

    func checkForChanges() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Security: Prevent saving sensitive clipboard items (e.g. from password managers)
        let types = pasteboard.types ?? []
        let sensitiveTypes: [NSPasteboard.PasteboardType] = [
            .init("org.nspasteboard.TransientType"),
            .init("org.nspasteboard.ConcealedType"),
            .init("com.agilebits.onepassword")
        ]

        for sensitiveType in sensitiveTypes {
            if types.contains(sensitiveType) {
                print("Ignored sensitive clipboard item of type: \(sensitiveType.rawValue)")
                return
            }
        }

        if let newString = pasteboard.string(forType: .string), !newString.isEmpty {
            // Check for any existing item with the same content to implement "move-to-top"
            let predicate = #Predicate<ClipboardItem> { $0.content == newString }
            var descriptor = FetchDescriptor<ClipboardItem>(predicate: predicate)
            descriptor.fetchLimit = 1
            
            do {
                let existingItems = try modelContext.fetch(descriptor)
                
                if let existingItem = existingItems.first {
                    // Item already exists - just update its timestamp to move it to top
                    existingItem.timestamp = Date()
                } else {
                    // New unique item - insert it
                    let item = ClipboardItem(content: newString)
                    modelContext.insert(item)
                }
                
                try modelContext.save()
                
                // Periodically prune old records based on retention settings
                pruneOldRecords()
            } catch {
                print("Failed to handle new clipboard item: \(error)")
            }
        }
    }
    
    func delete(item: ClipboardItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
    
    @AppStorage("historyRetentionDays") private var historyRetentionDays: Int = 180
    
    /// Deletes items older than the threshold set in settings
    private func pruneOldRecords() {
        guard historyRetentionDays > 0 else { return } // 0 means "Forever"
        
        let retentionDays = historyRetentionDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
        
        do {
            try modelContext.delete(model: ClipboardItem.self, where: #Predicate { item in
                item.timestamp < cutoff
            })
            try modelContext.save()
        } catch {
            print("Failed to prune old records: \(error)")
        }
    }
    
    func copyToClipboard(item: ClipboardItem) {
        copyToClipboard(content: item.content)
    }

    func copyToClipboard(content: String) {
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        // Update change count so we don't re-save what we just copied
        lastChangeCount = pasteboard.changeCount 
    }

    @AppStorage("shiftEnterApps") private var shiftEnterAppsJSON: String = "[]"
    
    private var shiftEnterBundleIDs: [String] {
        guard let data = shiftEnterAppsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func paste(item: ClipboardItem, isGlobalHotkey: Bool = false) {
        // Move to top by updating timestamp
        item.timestamp = Date()
        try? modelContext.save()
        
        paste(content: item.content, isGlobalHotkey: isGlobalHotkey)
    }

    func paste(content: String, isGlobalHotkey: Bool = false) {
        copyToClipboard(content: content)

        // If SmartClipboard's window is frontmost, hide it so focus returns to the
        // previous app. When triggered via global hotkey the app is already in the
        // background, so we skip the hide.
        let needsHide = !isGlobalHotkey && NSApp.isActive
        if needsHide {
            onPaste?()
            NSApp.hide(nil)
        }

        // Give the previously focused app time to reclaim focus before Cmd+V lands.
        let delay: Double = needsHide ? 0.15 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let src = CGEventSource(stateID: .combinedSessionState)

            // CMD down
            let cmdd = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
            // v down
            let vd = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            vd?.flags = .maskCommand
            // v up
            let vu = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vu?.flags = .maskCommand
            // CMD up
            let cmdu = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)

            cmdd?.post(tap: .cgAnnotatedSessionEventTap)
            vd?.post(tap: .cgAnnotatedSessionEventTap)
            vu?.post(tap: .cgAnnotatedSessionEventTap)
            cmdu?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    // MARK: - Global hotkey handlers

    /// Fetches the item at the given 0-based index (newest-first) and pastes it.
    func pasteItem(at index: Int) {
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = index + 1
        guard let items = try? modelContext.fetch(descriptor),
              index < items.count else { return }
        paste(item: items[index], isGlobalHotkey: true)
    }

    /// Fetches the most-recent `count` items and pastes them oldest→newest.
    func pasteMultiple(count: Int) {
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = count
        guard let items = try? modelContext.fetch(descriptor) else { return }
        // Reverse so oldest lands in the target app first
        pasteSequentially(Array(items.prefix(count).reversed()))
    }

    private func pasteSequentially(_ items: [ClipboardItem], index: Int = 0) {
        guard index < items.count else { return }
        
        // Paste current item
        paste(content: items[index].content, isGlobalHotkey: true)
        
        // If there are more items, send an Enter/Shift+Enter to separate them
        if index < items.count - 1 {
            let delay: Double = 0.15 // Slight delay to ensure paste finished
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let src = CGEventSource(stateID: .combinedSessionState)
                
                // Determine if we need Shift+Enter vs Enter
                let activeApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let useShift = activeApp != nil && self.shiftEnterBundleIDs.contains(activeApp!)
                
                if useShift {
                    // Send Shift+Enter to avoid submission
                    let shdown = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: true)
                    let retd = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true)
                    retd?.flags = .maskShift
                    let retu = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false)
                    retu?.flags = .maskShift
                    let shup = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: false)
                    
                    shdown?.post(tap: .cgAnnotatedSessionEventTap)
                    retd?.post(tap: .cgAnnotatedSessionEventTap)
                    retu?.post(tap: .cgAnnotatedSessionEventTap)
                    shup?.post(tap: .cgAnnotatedSessionEventTap)
                } else {
                    // Send standard Enter
                    let retd = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true)
                    let retu = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false)
                    retd?.post(tap: .cgAnnotatedSessionEventTap)
                    retu?.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
        }

        // Increase delay between items slightly for reliability
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.pasteSequentially(items, index: index + 1)
        }
    }
}
