import SwiftUI
import AppKit
import SwiftData

/// Manages the menu bar icon (NSStatusItem) and provides custom left-click/right-click behavior.
extension Notification.Name {
    static let uiWillShow = Notification.Name("uiWillShow")
    static let settingsWillShow = Notification.Name("settingsWillShow")
    static let closeUI = Notification.Name("closeUI")
}

/// A custom NSPanel that allows becoming the key window even without a title bar.
/// This ensures the search bar and keyboard navigation work correctly.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private var sharedSettingsWindow: NSWindow?

@MainActor
func presentSettingsWindow(manager: ClipboardManager, importManager: ImportManager, container: ModelContainer, excluding excludedWindow: NSWindow? = nil, closeUIAfterOpen: Bool = false) {
    NotificationCenter.default.post(name: .settingsWillShow, object: nil)
    
    if sharedSettingsWindow == nil {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        
        let hostingController = NSHostingController(
            rootView: SettingsView()
                .ignoresSafeArea(.all, edges: .top)
                .environmentObject(manager)
                .environmentObject(importManager)
                .modelContainer(container)
        )
        window.contentViewController = hostingController
        window.center()
        
        sharedSettingsWindow = window
    }

    NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    NSApp.activate(ignoringOtherApps: true)

    let bringSettingsToFront = {
        guard let settingsWindow = sharedSettingsWindow else { return }

        let candidateWindows = NSApp.windows.filter { window in
            guard window !== excludedWindow else { return false }
            guard window.isVisible else { return false }
            return !(window is NSPanel)
        }

        settingsWindow.collectionBehavior.insert(.moveToActiveSpace)
        if !candidateWindows.contains(where: { $0 === settingsWindow }) {
            settingsWindow.center()
        }
        settingsWindow.orderFrontRegardless()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    DispatchQueue.main.async(execute: bringSettingsToFront)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: bringSettingsToFront)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        bringSettingsToFront()
        if closeUIAfterOpen {
            NotificationCenter.default.post(name: .closeUI, object: nil)
        }
    }
}

@MainActor
final class StatusItemManager: NSObject {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSPanel?
    
    private let clipboardManager: ClipboardManager
    private let importManager: ImportManager
    private let modelContainer: ModelContainer
    
    init(clipboardManager: ClipboardManager, importManager: ImportManager, modelContainer: ModelContainer) {
        self.clipboardManager = clipboardManager
        self.importManager = importManager
        self.modelContainer = modelContainer
        super.init()
        
        setupStatusItem()
        setupMainWindow()
        
        clipboardManager.onPaste = { [weak self] in
            DispatchQueue.main.async { self?.closeUI() }
        }
        
        GlobalHotkeyManager.shared.onToggleUI = { [weak self] in
            DispatchQueue.main.async { self?.toggleMainWindow(fromStatusItem: false) }
        }

        NotificationCenter.default.addObserver(forName: .closeUI, object: nil, queue: .main) { [weak self] _ in
            self?.closeUI()
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
    
    private func setupMainWindow() {
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.borderless],
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
            .environmentObject(importManager)
            .modelContainer(modelContainer)
        
        panel.contentViewController = NSHostingController(rootView: contentView)
        self.mainWindow = panel
    }
    
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            toggleMainWindow(fromStatusItem: true)
        }
    }
    
    private func toggleMainWindow(fromStatusItem: Bool) {
        guard let window = mainWindow else { return }

        let isActuallyFrontmost = window.isVisible
            && window.occlusionState.contains(.visible)
            && NSApp.isActive
            && NSApp.keyWindow === window

        if isActuallyFrontmost {
            window.orderOut(nil)
        } else {
            NotificationCenter.default.post(name: .uiWillShow, object: nil, userInfo: ["isInPopover": false])
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
            
            if fromStatusItem, let button = statusItem?.button, let statusBarWindow = button.window, let screen = statusBarWindow.screen {
                let rectInWindow = button.convert(button.bounds, to: nil)
                let screenRect = statusBarWindow.convertToScreen(rectInWindow)
                let screenFrame = screen.visibleFrame
                
                let windowSize = window.frame.size
                var xPos = screenRect.midX - windowSize.width / 2
                let yPos = screenRect.minY - windowSize.height - 4
                
                if xPos < screenFrame.minX {
                    xPos = screenFrame.minX
                }
                if xPos + windowSize.width > screenFrame.maxX {
                    xPos = screenFrame.maxX - windowSize.width
                }
                
                window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
            } else {
                window.center()
            }
            
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func closeUI() {
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
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit SmartClipboard", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func openSettings() {
        presentSettingsWindow(manager: clipboardManager, importManager: importManager, container: modelContainer, excluding: mainWindow)
    }
    
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}
