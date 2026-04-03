import SwiftUI

@main
struct SmartClipboardApp: App {
    var body: some Scene {
        // MenuBarExtra creates the icon in the top right of your Mac screen (Requires macOS 13+)
        MenuBarExtra("Smart Clipboard", systemImage: "doc.on.clipboard") {
            ContentView()
        }
        .menuBarExtraStyle(.window) // Makes it act like a popover window
    }
}
