import AppKit
import Carbon
import CoreGraphics

/// Registers system-wide hotkeys using the Carbon Event Manager.
/// Fires regardless of which application is currently frontmost.
final class GlobalHotkeyManager {

    static let shared = GlobalHotkeyManager()

    /// Called on the main actor with the 0-based index of the item to paste.
    var onPasteItem: ((Int) -> Void)?

    /// Called on the main actor with the count of recent items to paste in sequence.
    var onPasteMultiple: ((Int) -> Void)?

    /// Called on the main actor for Option+V (Cmd+A then Cmd+V).
    var onSelectAllAndPaste: (() -> Void)?

    /// Called on the main actor for Option+C (Cmd+A then Cmd+C).
    var onSelectAllAndCopy: (() -> Void)?

    /// Called when the "Toggle UI" hotkey is fired (legacy).
    var onToggleUI: (() -> Void)?

    /// Called when the trigger hotkey is pressed down.
    var onTriggerKeyDown: (() -> Void)?

    /// Called when the trigger hotkey is released.
    var onTriggerKeyUp: (() -> Void)?

    /// Called with a relative delta (+1 = down/next, -1 = up/previous) during quick select scroll.
    var onNavigate: ((Int) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var selectAllKeyRefs: [EventHotKeyRef?] = []
    private var toggleUIKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    // MARK: Scroll tap (active only during quick select)
    private var scrollTap: CFMachPort?
    private var scrollRunLoopSource: CFRunLoopSource?
    private var scrollAccumulator: Double = 0

    private let cmdKey = 0x0100
    private let optionKey = 0x0800
    private let controlKey = 0x1000
    private let shiftKey = 0x0200

    private init() {}

    // MARK: - Public API

    func install() {
        guard eventHandler == nil else { return }

        var specs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event = event, let userData = userData else { return noErr }

                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    UInt32(kEventParamDirectObject),
                    UInt32(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )

                let mgr = Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                let id = Int(hkID.id)
                let eventKind = Int(GetEventKind(event))

                Task { @MainActor in
                    print("[GlobalHotkeyManager] Hotkey event: ID \(id), kind: \(eventKind)")
                    
                    if id == 100 {
                        if eventKind == kEventHotKeyPressed {
                            mgr.onToggleUI?()
                            mgr.onTriggerKeyDown?()
                        } else if eventKind == kEventHotKeyReleased {
                            mgr.onTriggerKeyUp?()
                        }
                    } else if eventKind == kEventHotKeyPressed {
                        if id >= 1 && id <= 10 {
                            // Cmd+1…9 → index 0…8; Cmd+0 → index 9
                            let index = (id == 10) ? 9 : id - 1
                            print("[GlobalHotkeyManager] Pasting index: \(index)")
                            mgr.onPasteItem?(index)
                        } else if id >= 11 && id <= 19 {
                            // Option+1…9 → paste last N items
                            let count = id - 10
                            print("[GlobalHotkeyManager] Pasting multiple: \(count)")
                            mgr.onPasteMultiple?(count)
                        } else if id == 20 {
                            // Option+V → Cmd+A, Cmd+V
                            print("[GlobalHotkeyManager] Option+V (Select All & Paste)")
                            mgr.onSelectAllAndPaste?()
                        } else if id == 21 {
                            // Option+C → Cmd+A, Cmd+C
                            print("[GlobalHotkeyManager] Option+C (Select All & Copy)")
                            mgr.onSelectAllAndCopy?()
                        }
                    }
                }
                return noErr
            },
            2, &specs, selfPtr, &eventHandler
        )

        registerHotkeys()
    }

    func uninstall() {
        hotKeyRefs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()

        selectAllKeyRefs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        selectAllKeyRefs.removeAll()

        if let ref = toggleUIKeyRef {
            UnregisterEventHotKey(ref)
            toggleUIKeyRef = nil
        }

        if let h = eventHandler {
            RemoveEventHandler(h)
            eventHandler = nil
        }

        stopScrollTap()
    }

    /// Dynamically register or unregister the global Option+V and Option+C Select All hotkeys.
    func updateSelectAllHotkeys(enabled: Bool) {
        selectAllKeyRefs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        selectAllKeyRefs.removeAll()

        guard enabled else {
            print("[GlobalHotkeyManager] Select All hotkeys (⌥V/⌥C) disabled")
            return
        }

        let sig = fourCC("SCLP")
        let optPairs: [(Int, Int)] = [
            (kVK_ANSI_V, 20), (kVK_ANSI_C, 21)
        ]
        for (key, id) in optPairs {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: sig, id: UInt32(id))
            RegisterEventHotKey(UInt32(key), UInt32(optionKey),
                                hkID, GetApplicationEventTarget(), 0, &ref)
            selectAllKeyRefs.append(ref)
        }
        print("[GlobalHotkeyManager] Select All hotkeys (⌥V/⌥C) registered")
    }

    // MARK: - Scroll tap (quick select scroll-to-navigate)

    /// Start intercepting scroll wheel events to drive quick-select navigation.
    func startScrollTap() {
        guard scrollTap == nil else { return }
        scrollAccumulator = 0

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo -> Unmanaged<CGEvent>? in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<GlobalHotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return mgr.handleScrollEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("[GlobalHotkeyManager] Could not create scroll event tap (check Accessibility permission)")
            return
        }

        scrollTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        scrollRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[GlobalHotkeyManager] Scroll tap started")
    }

    /// Stop the scroll wheel event tap.
    func stopScrollTap() {
        if let tap = scrollTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = scrollRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        scrollTap = nil
        scrollRunLoopSource = nil
        scrollAccumulator = 0
        print("[GlobalHotkeyManager] Scroll tap stopped")
    }

    private func handleScrollEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        let intDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let pointDelta = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))

        if intDelta != 0 {
            // Discrete mouse wheel notch → immediate single step
            scrollAccumulator = 0
            let delta = intDelta > 0 ? -1 : 1  // scroll up = previous (-1), scroll down = next (+1)
            DispatchQueue.main.async { [weak self] in
                self?.onNavigate?(delta)
            }
        } else if pointDelta != 0 {
            // Continuous trackpad scrolling with accumulator (same threshold as QuickSelect: 6 pts)
            scrollAccumulator += pointDelta
            let threshold: Double = 6.0
            if scrollAccumulator >= threshold {
                scrollAccumulator = 0
                DispatchQueue.main.async { [weak self] in self?.onNavigate?(-1) }
            } else if scrollAccumulator <= -threshold {
                scrollAccumulator = 0
                DispatchQueue.main.async { [weak self] in self?.onNavigate?(1) }
            }
        }

        // Consume the scroll event so it doesn't reach the window underneath
        return nil
    }

    // MARK: - Private

    private func registerHotkeys() {
        let sig = fourCC("SCLP")

        // Cmd+1…9 → hotkey IDs 1…9; Cmd+0 → ID 10
        let cmdPairs: [(Int, Int)] = [
            (kVK_ANSI_1, 1), (kVK_ANSI_2, 2), (kVK_ANSI_3, 3),
            (kVK_ANSI_4, 4), (kVK_ANSI_5, 5), (kVK_ANSI_6, 6),
            (kVK_ANSI_7, 7), (kVK_ANSI_8, 8), (kVK_ANSI_9, 9),
            (kVK_ANSI_0, 10)
        ]
        for (key, id) in cmdPairs {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: sig, id: UInt32(id))
            RegisterEventHotKey(UInt32(key), UInt32(cmdKey),
                                hkID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }

        // Option+1…9 → hotkey IDs 11…19
        let optPairs: [(Int, Int)] = [
            (kVK_ANSI_1, 11), (kVK_ANSI_2, 12), (kVK_ANSI_3, 13),
            (kVK_ANSI_4, 14), (kVK_ANSI_5, 15), (kVK_ANSI_6, 16),
            (kVK_ANSI_7, 17), (kVK_ANSI_8, 18), (kVK_ANSI_9, 19)
        ]
        for (key, id) in optPairs {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: sig, id: UInt32(id))
            RegisterEventHotKey(UInt32(key), UInt32(optionKey),
                                hkID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }

        // Check user setting for Option+V / Option+C Select All hotkeys (default false)
        let isSelectAllEnabled = UserDefaults.standard.bool(forKey: "enableSelectAllHotkeys")
        updateSelectAllHotkeys(enabled: isSelectAllEnabled)
    }

    func registerToggleUIHotkey(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        // Unregister existing if any
        if let ref = toggleUIKeyRef {
            UnregisterEventHotKey(ref)
            toggleUIKeyRef = nil
        }

        var carbonModifiers: Int = 0
        if modifiers.contains(.command) { carbonModifiers |= cmdKey }
        if modifiers.contains(.option) { carbonModifiers |= optionKey }
        if modifiers.contains(.control) { carbonModifiers |= controlKey }
        if modifiers.contains(.shift) { carbonModifiers |= shiftKey }

        let sig = fourCC("SCLP")
        let hkID = EventHotKeyID(signature: sig, id: 100) // 100 for Toggle UI
        
        print("[GlobalHotkeyManager] Registering Toggle UI: key \(keyCode), mods \(carbonModifiers)")
        RegisterEventHotKey(UInt32(keyCode), UInt32(carbonModifiers),
                            hkID, GetApplicationEventTarget(), 0, &toggleUIKeyRef)
    }

    private func fourCC(_ s: String) -> OSType {
        s.unicodeScalars.reduce(OSType(0)) { ($0 << 8) | OSType($1.value) }
    }
}
