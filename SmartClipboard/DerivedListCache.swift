import Foundation

/// Memoizes the filtered and paginated clipboard lists.
///
/// Every arrow key used to re-filter all 15,624 SwiftData models three times
/// (deleted check, pinned split, unpinned split), which measured ~18 ms per
/// keypress. Those lists only change when the query, history, deleted set or
/// pin state changes, so they are computed once per change. Pagination is
/// cached separately because it only re-slices the first N rows.
final class DerivedListCache {

    struct Key: Equatable {
        var historyCount = 0
        var historyFirst: UUID?
        var historyLast: UUID?
        var query = ""
        var resultsCount = 0
        var resultsFirst: UUID?
        var deletedCount = 0
        var revision = 0
    }

    struct Snapshot {
        let filtered: [ClipboardItem]
        let display: [ClipboardItem]
        let indexMap: [UUID: Int]
        let displayIds: [UUID]
    }

    private struct DisplayKey: Equatable {
        let list: Key
        let limit: Int
    }

    private var key: Key?
    private var displayKey: DisplayKey?
    private var filtered: [ClipboardItem] = []
    private var display: [ClipboardItem] = []
    private var indexMap: [UUID: Int] = [:]
    private var displayIds: [UUID] = []

    func snapshot(key newKey: Key,
                  base: [ClipboardItem],
                  deleted: Set<UUID>,
                  limit: Int) -> Snapshot {
        if key != newKey { rebuildFiltered(newKey, base: base, deleted: deleted) }

        let newDisplayKey = DisplayKey(list: newKey, limit: limit)
        if displayKey != newDisplayKey { rebuildDisplay(newDisplayKey) }

        return Snapshot(filtered: filtered, display: display, indexMap: indexMap, displayIds: displayIds)
    }

    private func rebuildFiltered(_ newKey: Key, base: [ClipboardItem], deleted: Set<UUID>) {
        var pinned: [ClipboardItem] = []
        var unpinned: [ClipboardItem] = []
        pinned.reserveCapacity(min(base.count, 64))
        unpinned.reserveCapacity(min(base.count, 256))

        for item in base {
            if deleted.contains(item.id) { continue }
            if item.isPinned {
                pinned.append(item)
            } else {
                unpinned.append(item)
            }
        }

        filtered = pinned + unpinned
        key = newKey
        displayKey = nil
    }

    private func rebuildDisplay(_ newKey: DisplayKey) {
        display = Array(filtered.prefix(newKey.limit))

        var map = [UUID: Int]()
        map.reserveCapacity(display.count)
        for (index, item) in display.enumerated() { map[item.id] = index }

        indexMap = map
        displayIds = display.map(\.id)
        displayKey = newKey
    }
}
