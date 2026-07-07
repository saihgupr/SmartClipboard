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
    @StateObject private var importManager: ImportManager
    private var statusItemManager: StatusItemManager?

    init() {
        let container = sharedModelContainer
        let manager = ClipboardManager(modelContext: container.mainContext)
        _clipboardManager = StateObject(wrappedValue: manager)
        let impManager = ImportManager(modelContext: container.mainContext)
        _importManager = StateObject(wrappedValue: impManager)
        self.statusItemManager = StatusItemManager(clipboardManager: manager, importManager: impManager, modelContainer: container)
        
        // Check for updates in the background on launch
        Task {
            await UpdateManager.shared.checkForUpdates(manually: false)
        }
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(clipboardManager)
                .environmentObject(importManager)
                .modelContainer(sharedModelContainer)
        }
    }
}
