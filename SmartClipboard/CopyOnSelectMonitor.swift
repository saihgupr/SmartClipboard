import AppKit
import ApplicationServices

/// Copy-on-select: when the user highlights text in any app, copy it to the
/// system clipboard automatically (terminal-style primary selection).
///
/// Polls the focused Accessibility element's `kAXSelectedTextAttribute` and
/// writes non-empty selections to `NSPasteboard.general`. The existing
/// `ClipboardManager` polling picks the pasteboard change up and records it.
///
/// Default OFF. Enabled via Settings → General → "Copy on Select"
/// (`enableCopyOnSelect` in UserDefaults).
final class CopyOnSelectMonitor {

    static let shared = CopyOnSelectMonitor()
    private init() {}

    private var timer: Timer?
    private var lastCopiedSelection = ""

    /// In-progress selection that hasn't settled yet (user may still be dragging).
    private var pendingSelection: String?
    private var pendingSince: Date?

    /// How long a highlight must sit unchanged before we copy it. This keeps
    /// mid-drag intermediates off the pasteboard; only the settled text copies.
    private let settleInterval: TimeInterval = 0.5

    private let ownBundleIDs: Set<String> = ["com.saihgupr.SmartClipboard"]
    private let maxLength = 100_000

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
            lastCopiedSelection = ""
            pendingSelection = nil
            pendingSince = nil
            return
        }
        guard AXIsProcessTrusted() else { return }

        // Never steal selections from our own UI (detail view has selectable text).
        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier, ownBundleIDs.contains(bid) {
            return
        }
        // The main panel is a non-activating panel; NSApp may still be active
        // while the user highlights inside it. Skip then as well.
        if NSApp.isActive { return }

        guard let selection = currentSelectedText(), !selection.isEmpty else {
            // No highlight (clickaway/caret move) — drop any unsettled drag.
            pendingSelection = nil
            pendingSince = nil
            return
        }

        let pasteboardString = NSPasteboard.general.string(forType: .string)
        if selection == lastCopiedSelection && pasteboardString == selection {
            // Already copied and undisturbed — nothing to do.
            pendingSelection = nil
            pendingSince = nil
            return
        }

        // Debounce: while the highlight keeps changing the user is still
        // dragging, so wait until it sits still before copying.
        if pendingSelection != selection {
            pendingSelection = selection
            pendingSince = Date()
            return
        }
        guard let since = pendingSince,
              Self.pendingIsSettled(since: since, now: Date(), interval: settleInterval) else { return }
        pendingSelection = nil
        pendingSince = nil

        guard Self.shouldCopy(selection: selection,
                              lastCopied: lastCopiedSelection,
                              pasteboardString: pasteboardString) else {
            // Keep in sync when the pasteboard already holds this text
            // (e.g. user pressed Cmd+C manually) so we don't rewrite it.
            if pasteboardString == selection {
                lastCopiedSelection = selection
            }
            return
        }

        let truncated = String(selection.prefix(maxLength))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(truncated, forType: .string)
        lastCopiedSelection = selection
    }

    /// Pure decision helper, extracted for unit testing.
    static func shouldCopy(selection: String,
                           lastCopied: String,
                           pasteboardString: String?) -> Bool {
        if selection.isEmpty { return false }
        if selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if selection == lastCopied { return false }
        if pasteboardString == selection { return false }
        return true
    }

    /// Pure settle check for the drag debounce, extracted for unit testing.
    static func pendingIsSettled(since: Date, now: Date, interval: TimeInterval) -> Bool {
        now.timeIntervalSince(since) >= interval
    }

    /// Returns the currently highlighted text in the frontmost app via
    /// Accessibility, or nil when there is no selection / not applicable.
    private func currentSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focusedRef) == .success,
              let focusedRef else { return nil }
        // swiftlint:disable:next force_cast
        let focused = focusedRef as! AXUIElement

        // Never copy from password / secure fields.
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused,
                                          kAXRoleAttribute as CFString,
                                          &roleRef) == .success,
           let role = roleRef as? String,
           role == "AXSecureTextField" {
            return nil
        }

        var selRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused,
                                            kAXSelectedTextAttribute as CFString,
                                            &selRef) == .success else { return nil }
        guard let text = selRef as? String, !text.isEmpty else { return nil }
        return text
    }
}
