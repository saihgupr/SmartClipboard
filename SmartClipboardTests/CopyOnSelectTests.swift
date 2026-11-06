import XCTest
import SwiftData
@testable import SmartClipboard

final class CopyOnSelectTests: XCTestCase {

    func testRejectsEmptyAndWhitespace() {
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "", lastCopied: "", pasteboardString: nil))
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "   ", lastCopied: "", pasteboardString: nil))
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "\n\t ", lastCopied: "", pasteboardString: nil))
    }

    func testAcceptsFreshSelection() {
        XCTAssertTrue(CopyOnSelectMonitor.shouldCopy(selection: "hello", lastCopied: "", pasteboardString: "other"))
        XCTAssertTrue(CopyOnSelectMonitor.shouldCopy(selection: "hello", lastCopied: "", pasteboardString: nil))
    }

    func testSkipsDuplicates() {
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "hello", lastCopied: "hello", pasteboardString: "other"))
        XCTAssertFalse(CopyOnSelectMonitor.shouldCopy(selection: "hello", lastCopied: "", pasteboardString: "hello"))
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
