import AppKit
import ApplicationServices
import os.log

/// Handles text injection when an AppKit drag-and-drop is not accepted by the target.
///
/// Strategy:
///   1. AXUIElement write — sets kAXSelectedTextAttribute on the focused AX element.
///   2. Clipboard + CGEventPostToPid — writes to pasteboard then sends ⌘V directly
///      to the target app's PID (bypasses focus/activation entirely).
///
/// Log filtering (Console.app):
///   Process = SmartClipboard, search: DragFallback
final class DragFallbackInjector {

    static let shared = DragFallbackInjector()
    private init() {}

    private let log = OSLog(subsystem: "com.saihgupr.SmartClipboard", category: "DragFallback")

    struct TargetInfo {
        let pid: pid_t
        let name: String
        let isAntigravity: Bool
    }

    // MARK: - Public entry point

    func handleDragEnd(text: String, at screenPoint: NSPoint, operation: NSDragOperation) {
        guard !text.isEmpty else { return }

        let enabled = UserDefaults.standard.object(forKey: "enableDragFallbackPaste") as? Bool ?? true
        guard enabled else {
            os_log("[DragFallback] Disabled by user setting.", log: log, type: .info)
            return
        }

        // Find the target app at the drop point
        guard let target = targetAppAtScreenPoint(screenPoint) else {
            os_log("[DragFallback] Drag ended. operation=%{public}lu screenPoint=(%{public}.0f,%{public}.0f) No target app window found.",
                   log: log, type: .info, operation.rawValue, screenPoint.x, screenPoint.y)
            return
        }

        os_log("[DragFallback] Drag ended. operation=%{public}lu screenPoint=(%{public}.0f,%{public}.0f) target='%{public}s' pid=%{public}d isAntigravity=%{public}d text.count=%{public}d",
               log: log, type: .info,
               operation.rawValue, screenPoint.x, screenPoint.y,
               target.name, target.pid, target.isAntigravity ? 1 : 0, text.count)

        // For non-Antigravity apps: if it's a clean native accept (.copy, .move, .link), skip fallback to avoid double-paste
        let cleanlyAccepted: NSDragOperation = [.copy, .move, .link]
        if !target.isAntigravity && !operation.intersection(cleanlyAccepted).isEmpty {
            os_log("[DragFallback] Clean native accept by '%{public}s' (op=%{public}lu) — skipping fallback.",
                   log: log, type: .info, target.name, operation.rawValue)
            return
        }

        os_log("[DragFallback] Triggering fallback for '%{public}s' (isAntigravity=%{public}d, op=%{public}lu) in 200ms.",
               log: log, type: .info, target.name, target.isAntigravity ? 1 : 0, operation.rawValue)

        // Activate the target application so focus returns to it
        if let targetApp = NSRunningApplication(processIdentifier: target.pid) {
            targetApp.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            guard let self else { return }
            self.injectText(text, target: target)
        }
    }

    // MARK: - Find target window

    /// Returns target info for the topmost standard app window at the given AppKit screen point (excluding ourselves and WindowServer).
    private func targetAppAtScreenPoint(_ screenPoint: NSPoint) -> TargetInfo? {
        // AppKit: origin bottom-left of primary display.
        // CoreGraphics: origin top-left of primary display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(x: screenPoint.x, y: primaryHeight - screenPoint.y)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourPID = pid_t(ProcessInfo.processInfo.processIdentifier)

        for info in windowList {
            guard
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                pid != ourPID,
                let ownerName = info[kCGWindowOwnerName as String] as? String,
                ownerName != "Window Server",
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let alpha = info[kCGWindowAlpha as String] as? CGFloat,
                alpha > 0.01,
                let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let rect = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            if rect.contains(cgPoint) {
                let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
                let isAntigravity = ownerName.localizedCaseInsensitiveContains("antigravity")
                    || bundleID.localizedCaseInsensitiveContains("antigravity")
                return TargetInfo(pid: pid, name: ownerName, isAntigravity: isAntigravity)
            }
        }

        return nil
    }

    // MARK: - Injection dispatch

    private func injectText(_ text: String, target: TargetInfo) {
        if target.isAntigravity {
            os_log("[DragFallback] Target is Antigravity IDE — using clipboard paste directly (Chromium AX stubs do not insert text).", log: log, type: .info)
            clipboardPasteViaPID(text: text, targetPID: target.pid)
            return
        }

        os_log("[DragFallback] Attempting injection — AX first.", log: log, type: .info)

        if tryAXInjection(text: text) {
            os_log("[DragFallback] AX injection succeeded.", log: log, type: .info)
        } else {
            os_log("[DragFallback] AX failed — using clipboard+postToPid.", log: log, type: .info)
            clipboardPasteViaPID(text: text, targetPID: target.pid)
        }
    }

    // MARK: - Strategy 1: AXUIElement

    private func tryAXInjection(text: String) -> Bool {
        guard AXIsProcessTrusted() else {
            os_log("[DragFallback] AX not trusted.", log: log, type: .info)
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else {
            os_log("[DragFallback] AX: no focused element.", log: log, type: .info)
            return false
        }

        // swiftlint:disable force_cast
        let focused = focusedRef as! AXUIElement
        // swiftlint:enable force_cast

        // Log the app title for diagnostics
        var topRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXTopLevelUIElementAttribute as CFString, &topRef)
        var titleRef: CFTypeRef?
        if let topEl = topRef { AXUIElementCopyAttributeValue(topEl as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) }
        os_log("[DragFallback] AX focused app: '%{public}s'", log: log, type: .info,
               (titleRef as? String) ?? "unknown")

        // Try inserting at caret
        if AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            os_log("[DragFallback] AX: kAXSelectedTextAttribute write OK.", log: log, type: .info)
            return true
        }

        // Try replacing full value
        var curRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &curRef)
        let newVal = ((curRef as? String) ?? "") + text
        if AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, newVal as CFTypeRef) == .success {
            os_log("[DragFallback] AX: kAXValueAttribute write OK.", log: log, type: .info)
            return true
        }

        os_log("[DragFallback] AX: both strategies failed.", log: log, type: .info)
        return false
    }

    // MARK: - Strategy 2: Clipboard + CGEventPostToPid

    private func clipboardPasteViaPID(text: String, targetPID: pid_t?) {
        let pasteboard = NSPasteboard.general

        // Snapshot clipboard
        let savedChangeCount = pasteboard.changeCount
        var savedItems: [[NSPasteboard.PasteboardType: Data]] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                var d: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types { if let data = item.data(forType: type) { d[type] = data } }
                savedItems.append(d)
            }
        }

        // Write payload
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        os_log("[DragFallback] Clipboard set (%{public}d chars). Sending ⌘V to pid=%{public}d.",
               log: log, type: .info, text.count, targetPID ?? -1)

        // Send ⌘V directly to the target PID (no focus required)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.postCmdV(toPID: targetPID)
            os_log("[DragFallback] ⌘V posted.", log: self.log, type: .info)

            // Restore clipboard after 800ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) { [weak self] in
                guard let self else { return }
                guard pasteboard.changeCount == savedChangeCount + 1 else {
                    os_log("[DragFallback] Clipboard modified externally — skipping restore.", log: self.log, type: .info)
                    return
                }
                pasteboard.clearContents()
                if !savedItems.isEmpty {
                    let restored = savedItems.map { d -> NSPasteboardItem in
                        let item = NSPasteboardItem()
                        for (t, data) in d { item.setData(data, forType: t) }
                        return item
                    }
                    pasteboard.writeObjects(restored)
                }
                os_log("[DragFallback] Clipboard restored.", log: self.log, type: .info)
            }
        }
    }

    /// Posts a ⌘V event. If `pid` is provided, sends directly to that process (no focus needed).
    /// Falls back to session event tap if PID is unknown.
    private func postCmdV(toPID pid: pid_t?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let cmdFlag = CGEventFlags(rawValue: UInt64(NSEvent.ModifierFlags.command.rawValue) | 0x000008)
        let vCode: CGKeyCode = 0x09 // kVK_ANSI_V

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false)
        else { return }

        keyDown.flags = cmdFlag
        keyUp.flags   = cmdFlag

        if let pid {
            // Direct delivery — bypasses focus requirements
            keyDown.postToPid(pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                keyUp.postToPid(pid)
            }
        } else {
            keyDown.post(tap: .cgSessionEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                keyUp.post(tap: .cgSessionEventTap)
            }
        }
    }
}
