import SwiftUI
import AppKit
import SwiftData

/// Manages the menu bar icon (NSStatusItem) and provides custom left-click/right-click behavior.
final class StatusItemManager: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    private let clipboardManager: ClipboardManager
    private let modelContainer: ModelContainer
    
    init(clipboardManager: ClipboardManager, modelContainer: ModelContainer) {
        self.clipboardManager = clipboardManager
        self.modelContainer = modelContainer
        super.init()
        
        setupStatusItem()
        setupPopover()
        
        // Register the "Toggle UI" hotkey trigger
        GlobalHotkeyManager.shared.onToggleUI = { [weak self] in
            DispatchQueue.main.async {
                self?.toggleUI()
            }
        }
        
        // Initial hotkey registration
        registerSavedHotkey()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Smart Clipboard")
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            
            // Allow receiving right-click events
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.behavior = .transient
        
        // Wrap ContentView in a hosting controller with proper environment and model container
        let contentView = ContentView()
            .environmentObject(clipboardManager)
            .modelContainer(modelContainer)
        
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
    }
    
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            toggleUI()
        }
    }
    
    func toggleUI() {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if popover.isShown {
            popover.performClose(button)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    private func registerSavedHotkey() {
        let keyCode = UserDefaults.standard.integer(forKey: "toggleUIKeyCode")
        let modifiersRaw = UserDefaults.standard.integer(forKey: "toggleUIModifiers")
        
        // Only register if we have a valid keyCode (0 can be a valid keyCode but we check if set)
        if keyCode != 0 || modifiersRaw != 0 {
            GlobalHotkeyManager.shared.registerToggleUIHotkey(
                keyCode: keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw))
            )
        }
    }
    
    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit SmartClipboard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Reset so next left-click works correctly
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
