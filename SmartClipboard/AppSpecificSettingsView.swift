import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppSpecificSettingsView: View {
    @AppStorage("shiftEnterApps") private var shiftEnterAppsJSON: String = "[]"
    
    @State private var apps: [AppInfo] = []
    
    struct AppInfo: Identifiable, Hashable {
        let id: String // bundleIdentifier
        let name: String
        let icon: NSImage
        let path: URL
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Special Paste Apps")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: addApplication) {
                    Label("Add App", systemImage: "plus.circle")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            
            if apps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "apps.iphone.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No apps added yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Add apps where you want a 'Shift+Enter' before pasting (e.g. Slack, Discord, Messages).")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(apps, id: \.id) { app in
                        HStack(spacing: 12) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(app.id)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: { removeApplication(app) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(app.name)")
                            .help("Remove \(app.name)")
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            
            Text("SmartClipboard will inject a Shift+Enter before Cmd+V in these applications. Great for chat apps to avoid accidental sends.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .onAppear(perform: loadApps)
    }
    
    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        // Ensure the app is active so the panel gets focus
        NSApp.activate(ignoringOtherApps: true)
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                    var currentIDs = getIDs()
                    if !currentIDs.contains(bundleID) {
                        currentIDs.append(bundleID)
                        saveIDs(currentIDs)
                        loadApps()
                    }
                }
            }
        }
    }
    
    private func removeApplication(_ app: AppInfo) {
        var currentIDs = getIDs()
        currentIDs.removeAll { $0 == app.id }
        saveIDs(currentIDs)
        loadApps()
    }
    
    private func loadApps() {
        let ids = getIDs()
        var loadedApps: [AppInfo] = []
        
        for id in ids {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let name = FileManager.default.displayName(atPath: url.path)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                loadedApps.append(AppInfo(id: id, name: name, icon: icon, path: url))
            } else {
                // Keep the ID even if we can't find the app right now
                loadedApps.append(AppInfo(id: id, name: id, icon: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage(), path: URL(fileURLWithPath: "/")))
            }
        }
        
        self.apps = loadedApps
    }
    
    private func getIDs() -> [String] {
        guard let data = shiftEnterAppsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    
    private func saveIDs(_ ids: [String]) {
        if let data = try? JSONEncoder().encode(ids), let string = String(data: data, encoding: .utf8) {
            shiftEnterAppsJSON = string
        }
    }
}
