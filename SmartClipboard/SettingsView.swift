import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @AppStorage("themeStyle") private var themeStyle = "darkGlass"
    @State private var selectedTab: SettingsTab? = .general
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case intelligence
        case shortcuts
        case apps
        case migration
        case about
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .general: return "General"
            case .intelligence: return "Intelligence"
            case .shortcuts: return "Shortcuts"
            case .apps: return "Apps"
            case .migration: return "Migration"
            case .about: return "About"
            }
        }
        
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .intelligence: return "sparkles"
            case .shortcuts: return "command"
            case .apps: return "app.badge.checkmark.fill"
            case .migration: return "arrow.down.doc.fill"
            case .about: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.title, systemImage: tab.icon)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()
                
                Group {
                    if let tab = selectedTab {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 25) {
                                headerView(for: tab)
                                
                                switch tab {
                                case .general:
                                    GeneralSettingsView()
                                case .intelligence:
                                    IntelligenceSettingsView()
                                case .shortcuts:
                                    ShortcutsSettingsView()
                                case .apps:
                                    AppSpecificSettingsView()
                                case .migration:
                                    MigrationSettingsView()
                                case .about:
                                    AboutSettingsView()
                                }
                                
                                Spacer()
                            }
                            .padding(30)
                            .frame(maxWidth: 600, alignment: .leading)
                        }
                    } else {
                        Text("Select a category")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("")
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .frame(minWidth: 750, minHeight: 550)
        .preferredColorScheme((themeStyle == "dark" || themeStyle == "darkGlass") ? .dark : (themeStyle == "light" ? .light : nil))
        .onReceive(NotificationCenter.default.publisher(for: .settingsWillShow)) { _ in
            selectedTab = .general
        }
    }
    
    @ViewBuilder
    private func headerView(for tab: SettingsTab) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.blue.gradient)
                
                Text(tab.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            
            Text(description(for: tab))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 10)
    }
    
    private func description(for tab: SettingsTab) -> String {
        switch tab {
        case .general: return "Configure how SmartClipboard behaves on your system."
        case .intelligence: return "Power up your search and organization with Gemini AI."
        case .shortcuts: return "Manage keyboard interactions and quick navigation."
        case .apps: return "Customize behavior for specific applications."
        case .migration: return "Import history from other clipboard managers."
        case .about: return "Information about SmartClipboard and its developer."
        }
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("historyRetentionDays") private var historyRetentionDays: Int = 180
    @AppStorage("themeStyle") private var themeStyle = "darkGlass"
    @State private var dbSizeString = "Calculating..."

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Startup") {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch at Login")
                            .font(.system(size: 14, weight: .medium))
                        Text("Automatically start SmartClipboard when you log in.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .focusEffectDisabled()
                .onChange(of: launchAtLogin) { _, newValue in
                    updateLoginItem(enabled: newValue)
                }
            }
            
            SettingsSection(title: "Memory") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Clipboard Retention")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Picker("", selection: $historyRetentionDays) {
                            Text("7 Days").tag(7)
                            Text("30 Days").tag(30)
                            Text("90 Days").tag(90)
                            Text("180 Days").tag(180)
                            Text("1 Year").tag(365)
                            Text("Forever").tag(0)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    
                    Text("Controls how long clipboard items are kept before automatic deletion. Keeping history longer increases disk usage but provides more contextual memory.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Database Disk Usage")
                                .font(.system(size: 14, weight: .medium))
                            Text("The current size of your clipboard history database on disk.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(dbSizeString)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            SettingsSection(title: "Privacy") {
                Toggle(isOn: $clipboardManager.incognitoMode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Incognito Mode")
                            .font(.system(size: 14, weight: .medium))
                        Text("When enabled, copied items are marked as incognito, and disabling this mode permanently deletes them. (⌘⇧N)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .focusEffectDisabled()
            }

            SettingsSection(title: "Appearance") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Theme Style")
                            .font(.system(size: 14, weight: .medium))
                        Text("Choose between glassmorphism, solid dark, or solid light mode.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $themeStyle) {
                        Text("Glass").tag("glass")
                        Text("Dark Glass").tag("darkGlass")
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }
            }
        }
        .onAppear {
            updateDBSize()
        }
        .onChange(of: historyRetentionDays) { _, _ in
            // Prune happens when retention changes, so refresh size
            updateDBSize()
        }
    }
    
    private func updateDBSize() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbFolder = appSupportURL.appendingPathComponent("SmartClipboard")
        
        do {
            let files = try fileManager.contentsOfDirectory(at: dbFolder, includingPropertiesForKeys: [.fileSizeKey])
            var totalBytes: Int64 = 0
            for file in files {
                if file.lastPathComponent.hasPrefix("clipboardHistory") {
                    let resources = try file.resourceValues(forKeys: [.fileSizeKey])
                    if let size = resources.fileSize {
                        totalBytes += Int64(size)
                    }
                }
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
            formatter.countStyle = .file
            dbSizeString = formatter.string(fromByteCount: totalBytes)
        } catch {
            dbSizeString = "Unknown"
        }
    }
    
    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
}

// MARK: - Intelligence Settings
struct IntelligenceSettingsView: View {
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    @AppStorage("geminiModel") private var selectedModel: String = "gemini-2.5-flash"
    @AppStorage("semanticSearchDepth") private var semanticSearchDepth: Int = 200
    
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false
    
    private let geminiService = GeminiService()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Gemini Configuration") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.system(size: 14, weight: .medium))
                        
                        HStack {
                            SecureField("Enter Gemini API Key", text: $apiKey)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            
                            Button {
                                fetchModels()
                            } label: {
                                if isLoadingModels {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Verify")
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoadingModels || apiKey.isEmpty)
                        }
                        
                        HStack {
                            Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                                Label("Get Key from Google AI Studio", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                            
                            Spacer()
                            
                            if showSuccessMessage {
                                Text("Verified Successfully")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    if !availableModels.isEmpty {
                        Divider()
                        
                        HStack {
                            Text("AI Model")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Picker("", selection: $selectedModel) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 200)
                        }
                    }
                }
            }
            
            SettingsSection(title: "Contextual Depth") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Search Scan Depth")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("\(semanticSearchDepth) items")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Slider(value: Binding(get: {
                        Double(semanticSearchDepth)
                    }, set: { newValue in
                        semanticSearchDepth = Int(newValue)
                    }), in: 200...2000, step: 50)
                    .tint(.blue)
                    
                    Text("Higher values allow searching deeper into history but consume more tokens and may be slower. 500-1000 is recommended for most users.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            if availableModels.isEmpty && !apiKey.isEmpty {
                fetchModels()
            }
        }
    }
    
    func fetchModels() {
        isLoadingModels = true
        errorMessage = nil
        showSuccessMessage = false
        
        Task {
            do {
                let models = try await geminiService.fetchModels(apiKey: apiKey)
                await MainActor.run {
                    self.availableModels = models
                    withAnimation {
                        self.showSuccessMessage = true
                    }
                    
                    if !models.contains(selectedModel) && !models.isEmpty {
                        self.selectedModel = models.contains("gemini-2.5-flash") ? "gemini-2.5-flash" : (models.first ?? "")
                    }
                    self.isLoadingModels = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { self.showSuccessMessage = false }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Connection error: Check your API key or internet."
                    self.isLoadingModels = false
                }
            }
        }
    }
}

// MARK: - Shortcuts Settings
struct ShortcutsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Global Access") {
                ShortcutRecorderView()
            }
            
            SettingsSection(title: "List Interaction") {
                LeftArrowActionSettingView()
            }
        }
    }
}

// MARK: - Migration Settings
struct MigrationSettingsView: View {
    @EnvironmentObject private var importManager: ImportManager
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "External History") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Found an existing clipboard history in another app? Import it here to seamlessly transition to SmartClipboard.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    ImportRow(
                        name: "Alfred",
                        description: "Import recently copied text from Alfred history.",
                        bundleID: "com.runningwithcrayons.Alfred",
                        fallbackIcon: "a.circle.fill",
                        action: { importManager.importFromAlfred() },
                        isImporting: importManager.isImporting
                    )
                    
                    ImportRow(
                        name: "Keyboard Maestro",
                        description: "Import recently copied text from Keyboard Maestro history.",
                        bundleID: "com.stairways.keyboardmaestro.editor",
                        fallbackIcon: "keyboard",
                        action: { importManager.importFromKeyboardMaestro() },
                        isImporting: importManager.isImporting
                    )
                    
                    ImportRow(
                        name: "BetterTouchTool",
                        description: "Import recently copied text from BetterTouchTool history.",
                        bundleID: "com.hegenberg.BetterTouchTool",
                        fallbackIcon: "hand.tap.fill",
                        action: { importManager.importFromBetterTouchTool() },
                        isImporting: importManager.isImporting
                    )
                }
            }

            SettingsSection(title: "Clean Slate") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Remove all items from your current history. This is recommended before importing from another app to ensure a clean transition.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete All History Items")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .alert("Delete All History?", isPresented: $showDeleteConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Delete Everything", role: .destructive) {
                            clipboardManager.clearAllHistory()
                        }
                    } message: {
                        Text("This action cannot be undone. All clipboard items, including pinned and favorited items, will be permanently removed.")
                    }
                }
            }
            
            if let message = importManager.importMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if importManager.isImporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: message.contains("Successfully") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(message.contains("Successfully") ? .green : .orange)
                        }
                        
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - About Settings
struct AboutSettingsView: View {
    @StateObject private var updateManager = UpdateManager.shared
    @AppStorage("checkForUpdatesOnLaunch") private var checkForUpdatesOnLaunch = true
    
    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 20) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .shadow(radius: 6)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("SmartClipboard")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("A modern clipboard manager powered by Google Gemini.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            SettingsSection(title: "Software Updates") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $checkForUpdatesOnLaunch) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatically Check for Updates")
                                .font(.system(size: 13, weight: .medium))
                            Text("Keep SmartClipboard secure and up-to-date automatically.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .focusEffectDisabled()
                    
                    Divider()
                    
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Update Status")
                                .font(.system(size: 13, weight: .medium))
                            
                            switch updateManager.checkStatus {
                            case .idle:
                                Text("Check has not been performed yet.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            case .checking:
                                Text("Checking for updates...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            case .upToDate:
                                Text("SmartClipboard is up to date.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            case .updateAvailable(let version, _):
                                Text("Version \(version) is available.")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            case .failed(let error):
                                Text("Check failed: \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Spacer()
                        
                        // Action button
                        switch updateManager.checkStatus {
                        case .idle, .upToDate, .failed:
                            Button(action: { updateManager.checkForUpdates(manually: true) }) {
                                if updateManager.isChecking {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Check Now")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(updateManager.isChecking)
                        case .checking:
                            ProgressView()
                                .controlSize(.small)
                        case .updateAvailable(_, let url):
                            Link(destination: url) {
                                Text("Download")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/saihgupr/SmartClipboard")!) {
                    Label("GitHub Repository", systemImage: "link")
                }
                
                Link(destination: URL(string: "https://ko-fi.com/saihgupr")!) {
                    Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
}

// MARK: - Helper Views
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 16) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LeftArrowActionSettingView: View {
    @AppStorage("leftArrowAction") private var leftArrowAction: String = "googleSearch"
    @AppStorage("longLeftArrowAction") private var longLeftArrowAction: String = "delete"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Left Arrow Action")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Picker("", selection: $leftArrowAction) {
                    Text("Quick Copy").tag("quickCopy")
                    Text("Paste Plain Text").tag("pastePlainText")
                    Text("Pin").tag("pin")
                    Text("Favorite").tag("favorite")
                    Text("Google Search").tag("googleSearch")
                    Text("Delete Item").tag("delete")
                    Text("No Action").tag("none")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
            }
            
            Group {
                if leftArrowAction == "quickCopy" {
                    Text("Quick Copy: Pressing Left Arrow copies the item to your clipboard without closing the menu. Perfect for grabbing multiple items in a row.")
                } else if leftArrowAction == "pin" {
                    Text("Pin: Pressing Left Arrow toggles the pinned state. Pinned items stay at the top of your list.")
                } else if leftArrowAction == "favorite" {
                    Text("Favorite: Pressing Left Arrow marks the item as a favorite. Favorites are never auto-deleted but stay in their chronological position.")
                } else if leftArrowAction == "pastePlainText" {
                    Text("Paste plain text: pressing left arrow performs a paste and match style.")
                } else if leftArrowAction == "googleSearch" {
                    Text("Google Search: Pressing Left Arrow opens your default browser and searches for the contents of the selected item.")
                } else if leftArrowAction == "delete" {
                    Text("Delete: Pressing Left Arrow immediately removes the item from your history without closing the menu.")
                } else {
                    Text("None: Left Arrow is disabled in the main list.")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            
            Divider().padding(.vertical, 8)
            
            HStack {
                Text("Hold Left Arrow Action")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Picker("", selection: $longLeftArrowAction) {
                    Text("Quick Copy").tag("quickCopy")
                    Text("Paste Plain Text").tag("pastePlainText")
                    Text("Pin").tag("pin")
                    Text("Favorite").tag("favorite")
                    Text("Google Search").tag("googleSearch")
                    Text("Delete Item").tag("delete")
                    Text("No Action").tag("none")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
            }
            
            Group {
                if longLeftArrowAction == "quickCopy" {
                    Text("Quick Copy: Holding Left Arrow copies the item to your clipboard without closing the menu.")
                } else if longLeftArrowAction == "pin" {
                    Text("Pin: Holding Left Arrow toggles the pinned state. Pinned items stay at the top of your list.")
                } else if longLeftArrowAction == "favorite" {
                    Text("Favorite: Holding Left Arrow marks the item as a favorite. Favorites are never auto-deleted.")
                } else if longLeftArrowAction == "pastePlainText" {
                    Text("Paste plain text: holding left arrow performs a paste and match style.")
                } else if longLeftArrowAction == "googleSearch" {
                    Text("Google Search: Holding Left Arrow opens your default browser and searches for the contents of the selected item.")
                } else if longLeftArrowAction == "delete" {
                    Text("Delete: Holding Left Arrow immediately removes the item from your history.")
                } else {
                    Text("None: Holding Left Arrow does nothing.")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ImportRow: View {
    let name: String
    let description: String
    let bundleID: String
    let fallbackIcon: String
    let action: () -> Void
    let isImporting: Bool
    
    @State private var appIcon: NSImage?
    
    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 18))
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                }
            }
            .onAppear {
                fetchIcon()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                action()
            } label: {
                Text("Import")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isImporting)
        }
    }
    
    private func fetchIcon() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}

// MARK: - Segmented Toggle
struct SegmentedToggle: View {
    @Binding var isOn: Bool
    let options: (String, String)

    private let segmentWidth: CGFloat = 80
    private let height: CGFloat = 28

    var body: some View {
        ZStack(alignment: .leading) {
            // Track
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

            // Sliding pill
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
                .padding(3)
                .frame(width: segmentWidth)
                .offset(x: isOn ? segmentWidth : 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)

            // Labels
            HStack(spacing: 0) {
                segmentButton(options.0, active: !isOn) { isOn = false }
                segmentButton(options.1, active: isOn)  { isOn = true  }
            }
        }
        .frame(width: segmentWidth * 2, height: height)
    }

    @ViewBuilder
    private func segmentButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { action() }
        }) {
            Text(label)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .frame(width: segmentWidth, height: height)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            NSCursor.pointingHand.set() // always reset; macOS reverts on exit
        }
    }
}
