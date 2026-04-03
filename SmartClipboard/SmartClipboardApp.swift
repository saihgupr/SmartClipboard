import SwiftUI
import SwiftData

@main
struct SmartClipboardApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ClipboardItem.self,
        ])
        
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dataDir = appSupportDir.appendingPathComponent("SmartClipboard")
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let dbURL = dataDir.appendingPathComponent("clipboardHistory.sqlite")
        
        let modelConfiguration = ModelConfiguration(schema: schema, url: dbURL)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @StateObject private var clipboardManager: ClipboardManager

    init() {
        let container = sharedModelContainer
        _clipboardManager = StateObject(wrappedValue: ClipboardManager(modelContext: container.mainContext))
    }

    var body: some Scene {
        MenuBarExtra("Smart Clipboard", systemImage: "doc.on.clipboard") {
            ContentView()
                .environmentObject(clipboardManager)
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
