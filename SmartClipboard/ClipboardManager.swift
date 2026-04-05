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

        if let newString = pasteboard.string(forType: .string) {
            // Prevent saving duplicates back-to-back by checking the most recent item in DB
            let descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            var fetchLimitDescriptor = descriptor
            fetchLimitDescriptor.fetchLimit = 1
            
            do {
                let recentItems = try modelContext.fetch(fetchLimitDescriptor)
                if recentItems.first?.content != newString {
                    let item = ClipboardItem(content: newString)
                    modelContext.insert(item)
                    try modelContext.save()
                    
                    // Periodically prune. In a real app we might only do this once a day, but for safety:
                    pruneOldRecords()
                }
            } catch {
                print("Failed to save new clipboard item: \(error)")
            }
        }
    }
    
    /// Deletes items older than 6 months (approx 180 days)
    private func pruneOldRecords() {
        let sixMonthsAgo = Calendar.current.date(byAdding: .day, value: -180, to: Date())!
        
        do {
            try modelContext.delete(model: ClipboardItem.self, where: #Predicate { item in
                item.timestamp < sixMonthsAgo
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
        // Determine the target application's bundle identifier
        // If triggered via global hotkey, the frontmost app is the target.
        // If triggered via UI, SmartClipboard is currently active.
        let targetBundleID: String?
        if isGlobalHotkey {
            targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        } else {
            // This is trickier as we are currently frontmost. 
            // In many cases, we can try to guess or just allow it to handle global hotkeys mostly.
            // For now, we'll try to get the frontmost app *before* we hide. 
            // Better would be to have tracked this when the app was activated.
            targetBundleID = nil // We'll skip for UI triggers for now to be safe, or just check what's behind us.
        }

        copyToClipboard(content: content)

        // If SmartClipboard's window is frontmost, hide it so focus returns to the
        // previous app. When triggered via global hotkey the app is already in the
        // background, so we skip the hide.
        let needsHide = !isGlobalHotkey && NSApp.isActive
        if needsHide {
            NSApp.hide(nil)
        }

        // Give the previously focused app time to reclaim focus before Cmd+V lands.
        let delay: Double = needsHide ? 0.15 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let src = CGEventSource(stateID: .combinedSessionState)

            // Check if we should send Shift+Enter
            // If it was a UI trigger, we might have lost the targetBundleID above.
            // Let's re-fetch the frontmost app now that we've hidden ourselves.
            let activeApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let effectiveBundleID = targetBundleID ?? activeApp
            
            if !isGlobalHotkey, let bid = effectiveBundleID, self.shiftEnterBundleIDs.contains(bid) {
                print("[ClipboardManager] Injecting Shift+Enter for \(bid)")
                
                // Shift down
                let shdown = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: true)
                // Return down (with shift mask)
                let retd = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true)
                retd?.flags = .maskShift
                // Return up
                let retu = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false)
                retu?.flags = .maskShift
                // Shift up
                let shup = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: false)
                
                shdown?.post(tap: .cgAnnotatedSessionEventTap)
                retd?.post(tap: .cgAnnotatedSessionEventTap)
                retu?.post(tap: .cgAnnotatedSessionEventTap)
                shup?.post(tap: .cgAnnotatedSessionEventTap)
                
                // Tiny delay after Shift+Enter before Cmd+V
                Thread.sleep(forTimeInterval: 0.05)
            }

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
        paste(content: items[index].content, isGlobalHotkey: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pasteSequentially(items, index: index + 1)
        }
    }
}
