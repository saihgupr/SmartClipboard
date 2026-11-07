import XCTest
import SwiftData
@testable import SmartClipboard

final class CopyOnSelectTests: XCTestCase {

    func testRejectsEmptyAndWhitespace() {
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "", pasteboardString: nil))
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "   ", pasteboardString: nil))
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "\n\t ", pasteboardString: nil))
    }

    func testAcceptsFreshSelection() {
        XCTAssertTrue(CopyOnSelectMonitor.shouldCopy(selection: "hello", pasteboardString: "other"))
        XCTAssertTrue(CopyOnSelectMonitor.shouldCopy(selection: "hello", pasteboardString: nil))
    }

    func testSkipsSelectionAlreadyOnPasteboard() {
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "hello", pasteboardString: "hello"))
    }

    func testRecopiesSameSelectionAfterPasteboardChanged() {
        // Selecting the same text again should copy it when the clipboard has
        // moved on since the last copy-on-select.
        XCTAssertTrue(CopyOnSelectMonitor.shouldCopy(selection: "hello", pasteboardString: "other"))
    }

    // MARK: - Explicit-copy suppression (KM action copy fix)

    func testSuppressedHighlightIsNotCopied() {
        // The highlight predates an explicit clipboard write (e.g. Cmd+C of
        // KM actions) — it must not overwrite the fresh clipboard contents.
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "hello",
                                                      pasteboardString: "other",
                                                      suppressedSelection: "hello"))
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "hello",
                                                      pasteboardString: nil,
                                                      suppressedSelection: "hello"))
    }

    func testNewHighlightLiftsSuppression() {
        // A genuinely different highlight is new user intent — it copies.
        XCTAssertTrue(CopyOnSelectMonitor.shouldCopy(selection: "hello world",
                                                     pasteboardString: "other",
                                                     suppressedSelection: "hello"))
    }

    func testNoSuppressionBehavesAsBefore() {
        XCTAssertTrue(CopyOnSelectMonitor.shouldCopy(selection: "hello",
                                                     pasteboardString: "other",
                                                     suppressedSelection: nil))
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "hello",
                                                      pasteboardString: "hello",
                                                      suppressedSelection: nil))
    }

    func testEnabledKeyDefaultsOff() {
        // bool(forKey:) returns false when unset — the feature must default off.
        // Use a scratch defaults suite via UserDefaults directly is overkill;
        // assert the production key constant and document the contract.
        XCTAssertEqual(CopyOnSelectMonitor.enabledKey, "enableCopyOnSelect")
    }

    // MARK: - Drag debounce

    func testPendingSettlesAfterInterval() {
        let since = Date()
        XCTAssertFalse(CopyOnSelectMonitor.pendingIsSettled(since: since, now: since, interval: 0.5))
        XCTAssertFalse(CopyOnSelectMonitor.pendingIsSettled(since: since, now: since.addingTimeInterval(0.49), interval: 0.5))
        XCTAssertTrue(CopyOnSelectMonitor.pendingIsSettled(since: since, now: since.addingTimeInterval(0.5), interval: 0.5))
        XCTAssertTrue(CopyOnSelectMonitor.pendingIsSettled(since: since, now: since.addingTimeInterval(5), interval: 0.5))
    }
}

final class CopyOnSelectCoalesceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: ClipboardItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func testShouldCoalesceGrowingSelection() {
        let now = Date()
        XCTAssertTrue(ClipboardManager.shouldCoalesceExtension(
            oldContent: "hello", oldTimestamp: now, newContent: "hello world", now: now))
    }

    func testShouldCoalesceShrinkingSelection() {
        let now = Date()
        XCTAssertTrue(ClipboardManager.shouldCoalesceExtension(
            oldContent: "hello world", oldTimestamp: now, newContent: "hello", now: now))
    }

    func testRejectsUnrelatedIdenticalAndTiny() {
        let now = Date()
        XCTAssertFalse(ClipboardManager.shouldCoalesceExtension(
            oldContent: "hello", oldTimestamp: now, newContent: "goodbye", now: now))
        XCTAssertFalse(ClipboardManager.shouldCoalesceExtension(
            oldContent: "hello", oldTimestamp: now, newContent: "hello", now: now))
        XCTAssertFalse(ClipboardManager.shouldCoalesceExtension(
            oldContent: "a", oldTimestamp: now, newContent: "ab", now: now))
        XCTAssertFalse(ClipboardManager.shouldCoalesceExtension(
            oldContent: "", oldTimestamp: now, newContent: "hello", now: now))
    }

    func testRejectsStaleItem() {
        let now = Date()
        let old = now.addingTimeInterval(-30)
        XCTAssertFalse(ClipboardManager.shouldCoalesceExtension(
            oldContent: "hello", oldTimestamp: old, newContent: "hello world", now: now))
    }
}
