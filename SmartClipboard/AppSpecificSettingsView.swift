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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enhanced Insertion")
                            .font(.system(size: 14, weight: .medium))
                        Text("Inject Shift+Enter before pasting in these apps.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: addApplication) {
                        Label("Add App", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if apps.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "apps.iphone.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary.opacity(0.3))
                        
                        Text("No applications configured.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Button("Add Application", action: addApplication)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.05), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(apps, id: \.id) { app in
                            HStack(spacing: 12) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 28, height: 28)
                                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(app.id)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: { removeApplication(app) }) {
                                    Image(systemName: "minus.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(.plain)
                                .help("Remove \(app.name)")
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("SmartClipboard automatically detects these apps and adds a newline before pasting. This prevents instant-sending in chat apps like Slack or Discord.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
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
