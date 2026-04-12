import SwiftUI
import AppKit
import SwiftData

/// Manages the menu bar icon (NSStatusItem) and provides custom left-click/right-click behavior.
extension Notification.Name {
    static let uiWillShow = Notification.Name("uiWillShow")
}

/// A custom NSPanel that allows becoming the key window even without a title bar.
/// This ensures the search bar and keyboard navigation work correctly.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class StatusItemManager: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var mainWindow: NSPanel?
    
    private let clipboardManager: ClipboardManager
    private let modelContainer: ModelContainer
    
    init(clipboardManager: ClipboardManager, modelContainer: ModelContainer) {
        self.clipboardManager = clipboardManager
        self.modelContainer = modelContainer
        super.init()
        
        setupStatusItem()
        setupPopover()
        setupMainWindow()
        
        clipboardManager.onPaste = { [weak self] in
            DispatchQueue.main.async { self?.closeUI() }
        }
        
        GlobalHotkeyManager.shared.onToggleUI = { [weak self] in
            DispatchQueue.main.async { self?.toggleMainWindow() }
        }
        
        registerSavedHotkey()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Smart Clipboard")
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.behavior = .transient
        
        let contentView = ContentView(isInPopover: true)
            .environmentObject(clipboardManager)
            .modelContainer(modelContainer)
        
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
    }
    
    private func setupMainWindow() {
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        
        let contentView = ContentView(isInPopover: false)
            .environmentObject(clipboardManager)
            .modelContainer(modelContainer)
        
        panel.contentViewController = NSHostingController(rootView: contentView)
        self.mainWindow = panel
    }
    
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            togglePopover()
        }
    }
    
    private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(button)
        } else {
            mainWindow?.orderOut(nil)
            NotificationCenter.default.post(name: .uiWillShow, object: nil, userInfo: ["isInPopover": true])
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.makeKey()
                window.makeMain()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func toggleMainWindow() {
        guard let window = mainWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            if popover?.isShown == true { popover?.performClose(nil) }
            NotificationCenter.default.post(name: .uiWillShow, object: nil, userInfo: ["isInPopover": false])
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func closeUI() {
        if popover?.isShown == true { popover?.performClose(nil) }
        mainWindow?.orderOut(nil)
    }
    
    private func registerSavedHotkey() {
        let keyCode = UserDefaults.standard.integer(forKey: "toggleUIKeyCode")
        let modifiersRaw = UserDefaults.standard.integer(forKey: "toggleUIModifiers")
        if keyCode != 0 || modifiersRaw != 0 {
            GlobalHotkeyManager.shared.registerToggleUIHotkey(
                keyCode: keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw))
            )
        }
    }
    
    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit SmartClipboard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}
