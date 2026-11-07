import AppKit
import ApplicationServices

/// Copy-on-select: when the user highlights text in any app, copy it to the
/// system clipboard automatically (terminal-style primary selection).
///
/// Polls the focused Accessibility element's selection and writes non-empty
/// selections to `NSPasteboard.general`. The existing `ClipboardManager`
/// polling picks the pasteboard change up and records it.
///
/// Chromium/Electron apps (Dia, Chrome, VS Code, …) keep their accessibility
/// tree disabled until an assistive client opts in. Setting
/// `AXManualAccessibility` / `AXEnhancedUserInterface` on the application
/// element makes those apps expose the current selection. Selection lookup
/// falls back to text-marker and selected-range attributes for web views that
/// do not implement `AXSelectedText` on the focused node.
///
/// Default OFF. Enabled via Settings → General → "Copy on Select"
/// (`enableCopyOnSelect` in UserDefaults).
final class CopyOnSelectMonitor {

    static let shared = CopyOnSelectMonitor()
    private init() {}

    private var timer: Timer?

    /// In-progress selection that hasn't settled yet (user may still be dragging).
    private var pendingSelection: String?
    private var pendingSince: Date?

    /// How long a highlight must sit unchanged before we copy it. This keeps
    /// mid-drag intermediates off the pasteboard; only the settled text copies.
    private let settleInterval: TimeInterval = 0.5

    private let ownBundleIDs: Set<String> = ["com.saihgupr.SmartClipboard"]
    private let maxLength = 100_000

    /// The last app we opted into the accessibility tree. Chromium-based apps
    /// only expose selections after this is set; repeat it on app switches.
    private var accessibilityOptInPid: pid_t = 0

    /// Rate limit for the diagnostic "nothing selected" log line.
    private var lastNoSelectionLog = Date.distantPast

    /// UserDefaults key for the feature toggle. Default off (bool defaults to false).
    static let enabledKey = "enableCopyOnSelect"

    /// Diagnostic logging toggle (Settings writes are not exposed in the UI).
    static let debugKey = "copyOnSelectDebug"
    private static let debugLogURL = URL(fileURLWithPath: "/tmp/smartclipboard-copyonselect.log")

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    func start(pollInterval: TimeInterval = 0.4) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // Fire on common modes so it keeps working while menus scroll, etc.
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard isEnabled else {
            // Reset so re-enabling picks up the current selection fresh.
            pendingSelection = nil
            pendingSince = nil
            return
        }
        guard AXIsProcessTrusted() else { return }

        guard let front = NSWorkspace.shared.frontmostApplication else { return }

        // Never steal selections from our own UI (detail view has selectable text).
        if let bid = front.bundleIdentifier, ownBundleIDs.contains(bid) {
            return
        }
        // The main panel is a non-activating panel; NSApp may still be active
        // while the user highlights inside it. Skip then as well.
        if NSApp.isActive { return }

        // Chromium/Electron apps need this opt-in before they build an
        // accessibility tree that reports the current selection.
        enableAccessibilityIfNeeded(for: front)

        guard let result = currentSelectedText(in: front), !result.text.isEmpty else {
            // No highlight (clickaway/caret move) — drop any unsettled drag.
            pendingSelection = nil
            pendingSince = nil
            logNoSelection(app: front)
            return
        }

        let selection = result.text
        let copyText = String(selection.prefix(maxLength))
        let pasteboardString = NSPasteboard.general.string(forType: .string)

        // Debounce: while the highlight keeps changing the user is still
        // dragging, so wait until it sits still before copying.
        if selection != pendingSelection {
            pendingSelection = selection
            pendingSince = Date()
            debugLog("pending len=\(selection.count) via=\(result.method) front=\(front.bundleIdentifier ?? "?")")
            return
        }
        guard let since = pendingSince,
              Self.pendingIsSettled(since: since, now: Date(), interval: settleInterval) else { return }
        pendingSelection = nil
        pendingSince = nil

        guard Self.shouldCopy(selection: copyText, pasteboardString: pasteboardString) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText, forType: .string)
        debugLog("copied len=\(copyText.count) via=\(result.method) front=\(front.bundleIdentifier ?? "?")")
    }

    /// Pure decision helper, extracted for unit testing.
    static func shouldCopy(selection: String, pasteboardString: String?) -> Bool {
        if selection.isEmpty { return false }
        if selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if pasteboardString == selection { return false }
        return true
    }

    /// Pure settle check for the drag debounce, extracted for unit testing.
    static func pendingIsSettled(since: Date, now: Date, interval: TimeInterval) -> Bool {
        now.timeIntervalSince(since) >= interval
    }

    // MARK: - Accessibility

    /// Turns on the accessibility tree for apps that ship it disabled. This is
    /// a no-op (attribute unsupported) for ordinary AppKit apps.
    private func enableAccessibilityIfNeeded(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != accessibilityOptInPid else { return }
        accessibilityOptInPid = pid

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        let manual = AXUIElementSetAttributeValue(appElement,
                                                  "AXManualAccessibility" as CFString,
                                                  kCFBooleanTrue)
        let enhanced = AXUIElementSetAttributeValue(appElement,
                                                    "AXEnhancedUserInterface" as CFString,
                                                    kCFBooleanTrue)
        debugLog("opt-in \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")] manual=\(manual.rawValue) enhanced=\(enhanced.rawValue)")
    }

    /// Returns the currently highlighted text in the frontmost app via
    /// Accessibility, or nil when there is no selection / not applicable.
    private func currentSelectedText(in app: NSRunningApplication) -> (method: String, text: String)? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)

        if let focused = elementAttribute(appElement, kAXFocusedUIElementAttribute as CFString) {
            if let result = selectedText(from: focused) { return result }
            if hasUnreadableSelection(focused),
               let result = selectedTextFromAncestors(of: focused) { return result }
        }

        let systemWide = AXUIElementCreateSystemWide()
        if let focused = elementAttribute(systemWide, kAXFocusedUIElementAttribute as CFString) {
            if let result = selectedText(from: focused) { return result }
            if hasUnreadableSelection(focused),
               let result = selectedTextFromAncestors(of: focused) { return result }
        }

        if let window = elementAttribute(appElement, kAXFocusedWindowAttribute as CFString),
           let result = selectedText(from: window) {
            return result
        }

        return nil
    }

    /// True when the element reports a non-empty selected range even though we
    /// could not read its text. Web views can keep the text on an ancestor, so
    /// only spend the ancestor walk when there is real evidence of a selection.
    private func hasUnreadableSelection(_ element: AXUIElement) -> Bool {
        guard let rangeValue = rawAttribute(element, kAXSelectedTextRangeAttribute as CFString),
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return false }
        var cfRange = CFRange(location: 0, length: 0)
        return AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange) && cfRange.length > 0
    }

    private func selectedTextFromAncestors(of element: AXUIElement) -> (method: String, text: String)? {
        var current = element
        for _ in 0..<12 {
            guard let parent = elementAttribute(current, kAXParentAttribute as CFString) else { return nil }
            guard !CFEqual(parent, current) else { return nil }
            if let result = selectedText(from: parent) { return result }
            current = parent
        }
        return nil
    }

    /// Reads a selection using every attribute web views are known to expose.
    private func selectedText(from element: AXUIElement) -> (method: String, text: String)? {
        guard !isSecureField(element) else { return nil }

        if let text = stringAttribute(element, kAXSelectedTextAttribute as CFString), !text.isEmpty {
            return ("AXSelectedText", text)
        }

        if let markerRange = rawAttribute(element, "AXSelectedTextMarkerRange" as CFString) {
            for name in ["AXStringForTextMarkerRange", "AXAttributedStringForTextMarkerRange"] {
                if let text = parameterizedString(element, name as CFString, markerRange), !text.isEmpty {
                    return ("textMarkerRange", text)
                }
            }
        }

        if let rangeValue = rawAttribute(element, kAXSelectedTextRangeAttribute as CFString) {
            if let text = parameterizedString(element,
                                              kAXStringForRangeParameterizedAttribute as CFString,
                                              rangeValue),
               !text.isEmpty {
                return ("selectedTextRange", text)
            }
            if let text = textFromRangeValue(element, rangeValue), !text.isEmpty {
                return ("valueRange", text)
            }
        }

        return nil
    }

    private func isSecureField(_ element: AXUIElement) -> Bool {
        if let role = stringAttribute(element, kAXRoleAttribute as CFString), role == "AXSecureTextField" {
            return true
        }
        if let subrole = stringAttribute(element, kAXSubroleAttribute as CFString), subrole == "AXSecureTextField" {
            return true
        }
        return false
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        guard let value = rawAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func rawAttribute(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        stringFrom(rawAttribute(element, attribute))
    }

    private func parameterizedString(_ element: AXUIElement,
                                      _ attribute: CFString,
                                      _ parameter: AnyObject) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &value) == .success else {
            return nil
        }
        return stringFrom(value)
    }

    private func stringFrom(_ value: AnyObject?) -> String? {
        guard let value else { return nil }
        if let text = value as? String { return text }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }

    private func textFromRangeValue(_ element: AXUIElement, _ rangeValue: AnyObject) -> String? {
        guard CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length > 0 else { return nil }
        guard let fullText = stringAttribute(element, kAXValueAttribute as CFString) else { return nil }
        let nsText = fullText as NSString
        guard range.location >= 0,
              range.location + range.length <= nsText.length else { return nil }
        return nsText.substring(with: NSRange(location: range.location, length: range.length))
    }

    // MARK: - Diagnostics

    private func logNoSelection(app: NSRunningApplication) {
        guard UserDefaults.standard.bool(forKey: Self.debugKey) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastNoSelectionLog) >= 1 else { return }
        lastNoSelectionLog = now

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        let focused = elementAttribute(appElement, kAXFocusedUIElementAttribute as CFString)
        let role = focused.flatMap { stringAttribute($0, kAXRoleAttribute as CFString) } ?? "none"
        var selectionError: AXError = .failure
        if let focused {
            var value: CFTypeRef?
            selectionError = AXUIElementCopyAttributeValue(focused,
                                                           kAXSelectedTextAttribute as CFString,
                                                           &value)
        }
        debugLog("no-selection front=\(app.bundleIdentifier ?? "?") role=\(role) selErr=\(selectionError.rawValue)")
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: Self.debugKey) else { return }
        let line = "\(Date().timeIntervalSince1970) \(message())\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: Self.debugLogURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: Self.debugLogURL)
        }
    }
}
