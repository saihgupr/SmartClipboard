import AppKit
import Combine

struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    let content: String
    let timestamp: Date
}

class ClipboardManager: ObservableObject {
    @Published var history: [ClipboardItem] = []
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var timer: Timer?

    init() {
        lastChangeCount = pasteboard.changeCount
        startPolling()
    }

    func startPolling() {
        // Check the clipboard every 1 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func checkForChanges() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // If there's new text on the clipboard, save it
        if let newString = pasteboard.string(forType: .string) {
            // Prevent saving duplicates back-to-back
            if history.first?.content != newString {
                let item = ClipboardItem(id: UUID(), content: newString, timestamp: Date())
                DispatchQueue.main.async {
                    self.history.insert(item, at: 0)
                    // Keep memory light by only storing the last 100 items
                    if self.history.count > 100 {
                        self.history.removeLast()
                    }
                }
            }
        }
    }
    
    func copyToClipboard(item: ClipboardItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
        // Update change count so we don't re-save what we just copied
        lastChangeCount = pasteboard.changeCount 
    }
}
