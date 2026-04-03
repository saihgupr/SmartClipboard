import AppKit
import Combine
import SwiftData

@Model
final class ClipboardItem: Identifiable {
    @Attribute(.unique) let id: UUID
    let content: String
    let timestamp: Date
    
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

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        lastChangeCount = pasteboard.changeCount
        startPolling()
        
        // Run an initial pruning of old records
        pruneOldRecords()
    }

    func startPolling() {
        // Check the clipboard every 1 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
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
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
        // Update change count so we don't re-save what we just copied
        lastChangeCount = pasteboard.changeCount 
    }
}
