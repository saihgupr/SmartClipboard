import Carbon

/// Registers system-wide hotkeys using the Carbon Event Manager.
/// Fires regardless of which application is currently frontmost.
final class GlobalHotkeyManager {

    static let shared = GlobalHotkeyManager()

    /// Called on the main actor with the 0-based index of the item to paste.
    var onPasteItem: ((Int) -> Void)?

    /// Called on the main actor with the count of recent items to paste in sequence.
    var onPasteMultiple: ((Int) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    private let cmdKey = 0x0100
    private let optionKey = 0x0800

    private init() {}

    // MARK: - Public API

    func install() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

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

                Task { @MainActor in
                    print("[GlobalHotkeyManager] Hotkey fired: ID \(id)")
                    
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
                    }
                }
                return noErr
            },
            1, &spec, selfPtr, &eventHandler
        )

        registerHotkeys()
    }

    func uninstall() {
        hotKeyRefs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        if let h = eventHandler {
            RemoveEventHandler(h)
            eventHandler = nil
        }
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
    }

    private func fourCC(_ s: String) -> OSType {
        s.unicodeScalars.reduce(OSType(0)) { ($0 << 8) | OSType($1.value) }
    }
}
