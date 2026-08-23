import SwiftUI
import AppKit
import SwiftData

/// Manages the menu bar icon (NSStatusItem) and provides custom left-click/right-click behavior.
extension Notification.Name {
    static let uiWillShow = Notification.Name("uiWillShow")
    static let settingsWillShow = Notification.Name("settingsWillShow")
    static let closeUI = Notification.Name("closeUI")
    static let quickSelectTriggerReleased = Notification.Name("quickSelectTriggerReleased")
    static let cancelQuickSelectMode = Notification.Name("cancelQuickSelectMode")
    static let activateQuickSelectMode = Notification.Name("activateQuickSelectMode")
    static let quickSelectNavigate = Notification.Name("quickSelectNavigate")
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
    private var lastCloseTime: Date?
    
    private var triggerKeyDownTime: Date?
    private var wasWindowVisibleOnKeyDown = false
    private var isQuickSelectActive = false

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
        
        if let window = mainWindow {
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.lastCloseTime = Date()
                self?.isQuickSelectActive = false
            }
        }
        
        clipboardManager.onPaste = { [weak self] in
            DispatchQueue.main.async { self?.closeUI() }
        }
        
        GlobalHotkeyManager.shared.onTriggerKeyDown = { [weak self] in
            DispatchQueue.main.async { self?.handleTriggerKeyDown() }
        }
        
        GlobalHotkeyManager.shared.onTriggerKeyUp = { [weak self] in
            DispatchQueue.main.async { self?.handleTriggerKeyUp() }
        }

        GlobalHotkeyManager.shared.onNavigate = { delta in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .quickSelectNavigate,
                    object: nil,
                    userInfo: ["delta": delta]
                )
            }
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
            togglePopover()
        }
    }
    
    private func isWindowFrontmost() -> Bool {
        guard let window = mainWindow else { return false }
        return window.isVisible
            && window.occlusionState.contains(.visible)
            && NSApp.isActive
            && NSApp.keyWindow === window
    }

    private func handleTriggerKeyDown() {
        triggerKeyDownTime = Date()
        let isVisible = isWindowFrontmost()
        wasWindowVisibleOnKeyDown = isVisible

        if !isVisible {
            // Open in normal mode immediately; quick select activates only if held
            showMainWindow(relativeTo: nil, isQuickSelect: false)
        }

        // After the long-press threshold, switch into quick select mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.triggerKeyDownTime != nil else { return }
            self.isQuickSelectActive = true
            NotificationCenter.default.post(name: .activateQuickSelectMode, object: nil)
        }

        // Start scroll-to-navigate capture
        GlobalHotkeyManager.shared.startScrollTap()
    }

    private func handleTriggerKeyUp() {
        let duration = triggerKeyDownTime.map { Date().timeIntervalSince($0) } ?? 0
        triggerKeyDownTime = nil
        // Stop scroll capture regardless of outcome
        GlobalHotkeyManager.shared.stopScrollTap()
        
        if wasWindowVisibleOnKeyDown {
            if duration < 0.22 {
                // Quick tap while window was already open -> Close window
                closeUI()
            } else if isQuickSelectActive {
                // Held while window was open -> paste current selection
                NotificationCenter.default.post(name: .quickSelectTriggerReleased, object: nil)
            }
        } else {
            // Window was opened by this key press
            if duration >= 0.18 {
                // Key was held down -> Paste selected item
                NotificationCenter.default.post(name: .quickSelectTriggerReleased, object: nil)
            } else {
                // Quick tap (< 180ms) -> Keep open in standard search mode
                isQuickSelectActive = false
                NotificationCenter.default.post(name: .cancelQuickSelectMode, object: nil)
            }
        }
        isQuickSelectActive = false
    }

    private func showMainWindow(relativeTo button: NSButton?, isQuickSelect: Bool = false) {
        guard let window = mainWindow else { return }
        
        NotificationCenter.default.post(name: .uiWillShow, object: nil, userInfo: [
            "isInPopover": button != nil,
            "isQuickSelect": isQuickSelect
        ])
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        
        if let button = button, let buttonWindow = button.window {
            let buttonScreenRect = button.convert(button.bounds, to: nil)
            let buttonOrigin = buttonWindow.convertToScreen(buttonScreenRect).origin
            
            let windowWidth = window.frame.width
            let windowHeight = window.frame.height
            
            let screen = NSScreen.screens.first { $0.frame.contains(buttonOrigin) } ?? NSScreen.main ?? NSScreen.screens[0]
            let screenFrame = screen.visibleFrame
            
            var x = buttonOrigin.x + (button.bounds.width / 2) - (windowWidth / 2)
            var y = buttonOrigin.y - windowHeight + 11
            
            // Constrain within screen bounds
            if x < screenFrame.minX {
                x = screenFrame.minX + 10
            } else if x + windowWidth > screenFrame.maxX {
                x = screenFrame.maxX - windowWidth - 10
            }
            
            if y < screenFrame.minY {
                y = screenFrame.minY + 10
            }
            
            window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        } else {
            window.center()
        }
        
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
    
    private func togglePopover() {
        if let lastClose = lastCloseTime, Date().timeIntervalSince(lastClose) < 0.25 {
            lastCloseTime = nil
            return
        }
        
        if isWindowFrontmost() {
            closeUI()
        } else {
            showMainWindow(relativeTo: statusItem?.button, isQuickSelect: false)
        }
    }
    
    private func toggleMainWindow() {
        if isWindowFrontmost() {
            closeUI()
        } else {
            showMainWindow(relativeTo: nil, isQuickSelect: false)
        }
    }
    
    func closeUI() {
        isQuickSelectActive = false
        GlobalHotkeyManager.shared.stopScrollTap()
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
