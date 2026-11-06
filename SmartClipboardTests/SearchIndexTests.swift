import XCTest
import SwiftData
@testable import SmartClipboard

/// Locks in the search semantics that the performance work depends on:
/// the folded byte matcher, the parsed date/time query, and the cached lists.
final class SearchIndexTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let calendar = Calendar.current

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

    // MARK: - Helpers

    @discardableResult
    private func makeItem(_ content: String, date: Date = Date(), pinned: Bool = false) -> ClipboardItem {
        let item = ClipboardItem(content: content, timestamp: date, isPinned: pinned)
        context.insert(item)
        return item
    }

    private func makeEntry(_ content: String, date: Date) -> ClipboardSearchIndex.Entry {
        ClipboardSearchIndex.entry(for: .init(id: UUID(), content: content, timestamp: date))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Byte matcher

    func testMatcherIsCaseInsensitiveSubstring() {
        let haystack = ClipboardSearchIndex.fold("The Quick Brown Fox")
        XCTAssertTrue(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "quick")))
        XCTAssertTrue(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "QUICK BROWN")))
        XCTAssertFalse(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "quack")))
        XCTAssertTrue(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "")))
        XCTAssertTrue(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "quick brown fox")))
        XCTAssertFalse(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "fox quick")))
    }

    func testMatcherHandlesUnicode() {
        let haystack = ClipboardSearchIndex.fold("日本語のテキスト")
        XCTAssertTrue(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "日本")))
        XCTAssertFalse(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "中国")))

        let accents = ClipboardSearchIndex.fold("Café au lait")
        XCTAssertTrue(ClipboardSearchIndex.contains(accents, ClipboardSearchIndex.needle(for: "CAFÉ")))
        // Diacritics are not folded; this matches the old case-insensitive search.
        XCTAssertFalse(ClipboardSearchIndex.contains(accents, ClipboardSearchIndex.needle(for: "cafe")))
    }

    func testMatcherRequiresLiteralWhitespace() {
        let haystack = ClipboardSearchIndex.fold("api key")
        XCTAssertTrue(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "api key")))
        XCTAssertFalse(ClipboardSearchIndex.contains(haystack, ClipboardSearchIndex.needle(for: "apikey")))
    }

    // MARK: - Entry fields

    func testEntryStoresCalendarComponents() {
        let timestamp = date(2026, 7, 13, 14, 30)
        let entry = makeEntry("hello", date: timestamp)
        XCTAssertEqual(entry.month, 7)
        XCTAssertEqual(entry.day, 13)
        XCTAssertEqual(entry.weekday, calendar.component(.weekday, from: timestamp))
        XCTAssertEqual(entry.hour, 14)
        XCTAssertEqual(entry.minute, 30)
    }

    // MARK: - Time parsing

    func testParseTimeReadsHoursMinutesAndMeridiem() {
        XCTAssertEqual(ClipboardSearchIndex.parseTime("2:30 pm")?.hours, [14])
        XCTAssertEqual(ClipboardSearchIndex.parseTime("2:30 pm")?.minuteValue, 30)
        XCTAssertEqual(ClipboardSearchIndex.parseTime("2:30 pm")?.minuteDigits, 2)

        XCTAssertEqual(ClipboardSearchIndex.parseTime("9 am")?.hours, [9])
        XCTAssertNil(ClipboardSearchIndex.parseTime("9 am")?.minuteValue)

        XCTAssertEqual(ClipboardSearchIndex.parseTime("12 am")?.hours, [0])
        XCTAssertEqual(ClipboardSearchIndex.parseTime("12 pm")?.hours, [12])
        XCTAssertEqual(ClipboardSearchIndex.parseTime("10:1")?.hours, [10, 22])
        XCTAssertEqual(ClipboardSearchIndex.parseTime("10:1")?.minuteDigits, 1)
        XCTAssertEqual(ClipboardSearchIndex.parseTime("12:30")?.hours, [0, 12])
        XCTAssertEqual(ClipboardSearchIndex.parseTime("13:45")?.hours, [13])

        XCTAssertNil(ClipboardSearchIndex.parseTime("abc"))
        XCTAssertNil(ClipboardSearchIndex.parseTime("2026"))
    }

    // MARK: - Date query

    func testDateQueryMatchesTimeAndMinutePrefix() {
        let entry = makeEntry("x", date: date(2026, 7, 13, 14, 30))

        var query = ClipboardSearchIndex.DateQuery()
        query.hours = [14]
        query.minuteValue = 30
        query.minuteDigits = 2
        XCTAssertTrue(query.matches(entry))

        query.minuteValue = 31
        XCTAssertFalse(query.matches(entry))

        query.minuteValue = 3
        query.minuteDigits = 1
        XCTAssertTrue(query.matches(entry), "\"2:3\" should match minutes 30-39")

        query.minuteValue = nil
        query.minuteDigits = 0
        XCTAssertTrue(query.matches(entry), "hour-only query should match any minute")

        query.hours = [15]
        XCTAssertFalse(query.matches(entry))
    }

    func testDateQueryMatchesMonthAndDay() {
        let entry = makeEntry("x", date: date(2026, 7, 13, 14, 30))

        var query = ClipboardSearchIndex.DateQuery()
        query.month = 7
        query.day = 13
        XCTAssertTrue(query.matches(entry))

        query.day = 14
        XCTAssertFalse(query.matches(entry))
    }

    func testDateQueryMatchesWeekday() {
        let timestamp = date(2026, 7, 13, 14, 30)
        let entry = makeEntry("x", date: timestamp)

        var query = ClipboardSearchIndex.DateQuery()
        query.weekday = calendar.component(.weekday, from: timestamp)
        XCTAssertTrue(query.matches(entry))

        query.weekday = (query.weekday ?? 1) % 7 + 1
        XCTAssertFalse(query.matches(entry))
    }

    func testDateQueryMatchesTodayAndYesterday() {
        let start = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)!

        var query = ClipboardSearchIndex.DateQuery()
        query.todayStart = start
        query.tomorrowStart = tomorrow
        query.yesterdayStart = yesterday
        query.matchesToday = true

        XCTAssertTrue(query.matches(makeEntry("x", date: Date())))
        XCTAssertFalse(query.matches(makeEntry("x", date: calendar.date(byAdding: .day, value: -5, to: start)!)))

        query.matchesToday = false
        query.matchesYesterday = true
        XCTAssertTrue(query.matches(makeEntry("x", date: yesterday)))
        XCTAssertFalse(query.matches(makeEntry("x", date: Date())))
    }

    func testInactiveDateQueryMatchesNothing() {
        let query = ClipboardSearchIndex.DateQuery()
        XCTAssertFalse(query.isActive)
        XCTAssertFalse(query.matches(makeEntry("x", date: Date())))
    }

    // MARK: - Index wiring

    func testSearchIndexMapsIdsBackToItems() {
        let first = makeItem("alpha")
        let second = makeItem("beta")
        let index = ClipboardSearchIndex()
        index.replace(
            entries: [first, second].map {
                ClipboardSearchIndex.entry(for: .init(id: $0.id, content: $0.content, timestamp: $0.timestamp))
            },
            itemsById: [first.id: first, second.id: second]
        )

        XCTAssertTrue(index.isReady)
        XCTAssertEqual(index.items(for: [second.id, first.id]).map(\.content), ["beta", "alpha"])
        XCTAssertEqual(index.items(for: [UUID()]).count, 0)
    }

    // MARK: - Derived list cache

    func testDerivedListCacheOrdersPinnedFirstAndRespectsLimit() {
        let a = makeItem("a")
        let b = makeItem("b", pinned: true)
        let c = makeItem("c")
        let cache = DerivedListCache()
        let key = DerivedListCache.Key(
            historyCount: 3,
            historyFirst: a.id,
            historyLast: c.id,
            query: "",
            resultsCount: 0,
            resultsFirst: nil,
            deletedCount: 0,
            revision: 0
        )

        let snapshot = cache.snapshot(key: key, base: [a, b, c], deleted: [], limit: 2)
        XCTAssertEqual(snapshot.filtered.map(\.content), ["b", "a", "c"])
        XCTAssertEqual(snapshot.display.map(\.content), ["b", "a"])
        XCTAssertEqual(snapshot.displayIds, [b.id, a.id])
        XCTAssertEqual(snapshot.indexMap[b.id], 0)
        XCTAssertEqual(snapshot.indexMap[a.id], 1)
    }

    func testDerivedListCacheSkipsDeletedItems() {
        let a = makeItem("a")
        let b = makeItem("b")
        let cache = DerivedListCache()
        let key = DerivedListCache.Key(
            historyCount: 2,
            historyFirst: a.id,
            historyLast: b.id,
            query: "",
            resultsCount: 0,
            resultsFirst: nil,
            deletedCount: 1,
            revision: 0
        )

        let snapshot = cache.snapshot(key: key, base: [a, b], deleted: [a.id], limit: 10)
        XCTAssertEqual(snapshot.filtered.map(\.content), ["b"])
        XCTAssertEqual(snapshot.displayIds, [b.id])
    }

    func testDerivedListCacheRebuildsWhenRevisionChanges() {
        let a = makeItem("a")
        let b = makeItem("b")
        let cache = DerivedListCache()
        var key = DerivedListCache.Key(
            historyCount: 2,
            historyFirst: a.id,
            historyLast: b.id,
            query: "",
            resultsCount: 0,
            resultsFirst: nil,
            deletedCount: 0,
            revision: 0
        )

        XCTAssertEqual(cache.snapshot(key: key, base: [a, b], deleted: [], limit: 10).filtered.map(\.content), ["a", "b"])

        b.isPinned = true
        XCTAssertEqual(cache.snapshot(key: key, base: [a, b], deleted: [], limit: 10).filtered.map(\.content), ["a", "b"],
                       "unchanged key must reuse the cached list")

        key.revision = 1
        XCTAssertEqual(cache.snapshot(key: key, base: [a, b], deleted: [], limit: 10).filtered.map(\.content), ["b", "a"])
    }

    func testDerivedListCachePaginatesWithoutRebuildingFilteredList() {
        let items = (0..<10).map { makeItem("item \($0)") }
        let cache = DerivedListCache()
        let key = DerivedListCache.Key(
            historyCount: items.count,
            historyFirst: items.first?.id,
            historyLast: items.last?.id,
            query: "",
            resultsCount: 0,
            resultsFirst: nil,
            deletedCount: 0,
            revision: 0
        )

        let firstPage = cache.snapshot(key: key, base: items, deleted: [], limit: 4)
        XCTAssertEqual(firstPage.display.count, 4)

        let secondPage = cache.snapshot(key: key, base: items, deleted: [], limit: 8)
        XCTAssertEqual(secondPage.display.count, 8)
        XCTAssertEqual(secondPage.filtered.count, 10)
        XCTAssertEqual(secondPage.display.prefix(4).map(\.id), firstPage.display.map(\.id))
    }
}
