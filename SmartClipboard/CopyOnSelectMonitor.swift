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

    /// Last observed `NSPasteboard.general.changeCount`. An unexpected bump
    /// means something else wrote the clipboard (user pressed Cmd+C, a paste
    /// ran, another app copied) — the explicit copy wins and the currently
    /// highlighted text must not overwrite it.
    private var lastSeenChangeCount: Int?

    /// Highlight that was on screen when the clipboard last changed
    /// externally (or when we first started observing). It predates the
    /// clipboard contents, so it stays suppressed until the highlight itself
    /// changes. This is what keeps copy-on-select from clobbering structured
    /// copies such as Keyboard Maestro action selections.
    private var suppressedSelection: String?

    /// How long a highlight must sit unchanged before we copy it. This keeps
    /// mid-drag intermediates off the pasteboard; only the settled text copies.
    private let settleInterval: TimeInterval = 0.5

    private let ownBundleIDs: Set<String> = ["com.saihgupr.SmartClipboard"]
    private let maxLength = 100_000

    /// The last app we opted into the accessibility tree. Chromium-based apps
    /// only expose selections after this is set; repeat it on app switches.
    private var accessibilityOptInPid: pid_t = 0

    /// UserDefaults key for the feature toggle. Default off (bool defaults to false).
    static let enabledKey = "enableCopyOnSelect"

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
            suppressedSelection = nil
            lastSeenChangeCount = nil
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

        let pasteboard = NSPasteboard.general
        let currentChange = pasteboard.changeCount
        let isBaseline = (lastSeenChangeCount == nil)
        let externallyChanged = !isBaseline && currentChange != lastSeenChangeCount

        var selection = currentSelectedText(in: front)
        if selection == nil, isChromiumCandidate(front) {
            // Chromium/Electron apps need this opt-in before they build an
            // accessibility tree that reports the current selection. Only
            // attempted for those apps so ordinary AppKit apps (e.g. KM) are
            // never touched.
            enableAccessibilityIfNeeded(for: front)
            selection = currentSelectedText(in: front)
        }

        if isBaseline {
            // Whatever is highlighted right now predates us — treat it as
            // stale so we never clobber the pre-existing clipboard (which may
            // hold a structured copy like KM actions) until the highlight
            // actually changes.
            lastSeenChangeCount = currentChange
            pendingSelection = nil
            pendingSince = nil
            suppressedSelection = selection
            return
        }

        if externallyChanged {
            // Someone else wrote the clipboard while this text was
            // highlighted (user pressed Cmd+C, a paste ran, another app
            // copied). The explicit copy wins — suppress this highlight so a
            // later poll doesn't overwrite it with stale text.
            lastSeenChangeCount = currentChange
            pendingSelection = nil
            pendingSince = nil
            suppressedSelection = selection
            return
        }

        guard let sel = selection, !sel.isEmpty else {
            // No highlight (clickaway/caret move) — drop any unsettled drag
            // and lift any suppression; the next highlight is genuinely new.
            pendingSelection = nil
            pendingSince = nil
            suppressedSelection = nil
            return
        }

        let copyText = String(sel.prefix(maxLength))
        let pasteboardString = pasteboard.string(forType: .string)

        guard Self.shouldCopy(selection: copyText,
                              pasteboardString: pasteboardString,
                              suppressedSelection: suppressedSelection) else {
            return
        }
        // A highlight that isn't suppressed is genuinely new — it supersedes
        // any previously suppressed text.
        suppressedSelection = nil

        // Debounce: while the highlight keeps changing the user is still
        // dragging, so wait until it sits still before copying.
        if sel != pendingSelection {
            pendingSelection = sel
            pendingSince = Date()
            return
        }
        guard let since = pendingSince,
              Self.pendingIsSettled(since: since, now: Date(), interval: settleInterval) else { return }
        pendingSelection = nil
        pendingSince = nil

        pasteboard.clearContents()
        pasteboard.setString(copyText, forType: .string)
        lastSeenChangeCount = pasteboard.changeCount
    }

    /// Pure decision helper, extracted for unit testing.
    static func shouldCopy(selection: String,
                           pasteboardString: String?,
                           suppressedSelection: String? = nil) -> Bool {
        if selection.isEmpty { return false }
        if selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if let suppressed = suppressedSelection, selection == suppressed { return false }
        if pasteboardString == selection { return false }
        return true
    }

    /// Pure settle check for the drag debounce, extracted for unit testing.
    static func pendingIsSettled(since: Date, now: Date, interval: TimeInterval) -> Bool {
        now.timeIntervalSince(since) >= interval
    }

    // MARK: - Accessibility

    /// Whether the app is a known Chromium/Electron host whose accessibility
    /// tree ships disabled. Only those apps get the `AXManualAccessibility` /
    /// `AXEnhancedUserInterface` opt-in; ordinary AppKit apps are never
    /// touched. Matching is intentionally loose — a false positive just
    /// restores the old always-opt-in behavior for that app.
    private func isChromiumCandidate(_ app: NSRunningApplication) -> Bool {
        let bid = (app.bundleIdentifier ?? "").lowercased()
        guard !bid.isEmpty else { return false }
        let markers = ["chrome", "chromium", "electron", "vscode", "cursor",
                       "thebrowser", "browser", "arc", "brave", "edgemac",
                       "opera", "vivaldi", "slack", "discord", "obsidian",
                       "notion", "figma", "todesktop", "antigravity",
                       "spotify", "chatgpt", "orion"]
        return markers.contains { bid.contains($0) }
    }

    /// Turns on the accessibility tree for apps that ship it disabled. This is
    /// a no-op (attribute unsupported) for ordinary AppKit apps.
    private func enableAccessibilityIfNeeded(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != accessibilityOptInPid else { return }
        accessibilityOptInPid = pid

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        _ = AXUIElementSetAttributeValue(appElement,
                                         "AXManualAccessibility" as CFString,
                                         kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(appElement,
                                         "AXEnhancedUserInterface" as CFString,
                                         kCFBooleanTrue)
    }

    /// Returns the currently highlighted text in the frontmost app via
    /// Accessibility, or nil when there is no selection / not applicable.
    private func currentSelectedText(in app: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)

        if let focused = elementAttribute(appElement, kAXFocusedUIElementAttribute as CFString) {
            if let text = selectedText(from: focused) { return text }
            if hasUnreadableSelection(focused),
               let text = selectedTextFromAncestors(of: focused) { return text }
        }

        let systemWide = AXUIElementCreateSystemWide()
        if let focused = elementAttribute(systemWide, kAXFocusedUIElementAttribute as CFString) {
            if let text = selectedText(from: focused) { return text }
            if hasUnreadableSelection(focused),
               let text = selectedTextFromAncestors(of: focused) { return text }
        }

        if let window = elementAttribute(appElement, kAXFocusedWindowAttribute as CFString),
           let text = selectedText(from: window) {
            return text
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

    private func selectedTextFromAncestors(of element: AXUIElement) -> String? {
        var current = element
        for _ in 0..<12 {
            guard let parent = elementAttribute(current, kAXParentAttribute as CFString) else { return nil }
            guard !CFEqual(parent, current) else { return nil }
            if let text = selectedText(from: parent) { return text }
            current = parent
        }
        return nil
    }

    /// Reads a selection using every attribute web views are known to expose.
    private func selectedText(from element: AXUIElement) -> String? {
        guard !isSecureField(element) else { return nil }

        if let text = stringAttribute(element, kAXSelectedTextAttribute as CFString), !text.isEmpty {
            return text
        }

        if let markerRange = rawAttribute(element, "AXSelectedTextMarkerRange" as CFString) {
            for name in ["AXStringForTextMarkerRange", "AXAttributedStringForTextMarkerRange"] {
                if let text = parameterizedString(element, name as CFString, markerRange), !text.isEmpty {
                    return text
                }
            }
        }

        if let rangeValue = rawAttribute(element, kAXSelectedTextRangeAttribute as CFString) {
            if let text = parameterizedString(element,
                                              kAXStringForRangeParameterizedAttribute as CFString,
                                              rangeValue),
               !text.isEmpty {
                return text
            }
            if let text = textFromRangeValue(element, rangeValue), !text.isEmpty {
                return text
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
}
