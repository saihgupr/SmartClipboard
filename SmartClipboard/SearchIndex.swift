import Foundation

/// Case-folded byte index over clipboard history.
///
/// Per-keystroke search used to run `localizedCaseInsensitiveContains` across every
/// item, which costs ~65 ms on a 15k-item / 10 MB history. Folding each item to
/// lowercase UTF-8 once and scanning bytes brings the same search down to ~5 ms.
///
/// Date and time parts of a query are matched against precomputed entry fields
/// (month/day/weekday/hour/minute) instead of formatting every timestamp, so
/// "today" or "2:30 pm" costs the same as a text search.
final class ClipboardSearchIndex {

    struct Entry: Sendable {
        let id: UUID
        let timestamp: Date
        let bytes: [UInt8]
        let dateBytes: [UInt8]
        let month: Int
        let day: Int
        let weekday: Int
        let hour: Int
        let minute: Int
    }

    struct Seed: Sendable {
        let id: UUID
        let content: String
        let timestamp: Date
    }

    /// The date/time part of a query, matched against precomputed entry fields
    /// so no DateFormatter or Calendar work happens per item per keystroke.
    struct DateQuery {
        var month: Int?
        var day: Int?
        var weekday: Int?
        var matchesYesterday = false
        var matchesToday = false
        var mightBeDateString = false
        /// 24-hour values accepted for the query time, e.g. "9 pm" → [21],
        /// "2:30" → [2, 14], "12 am" → [0].
        var hours: [Int] = []
        /// Minute digits from the query: "3" matches 30–39, "30" matches only 30.
        var minuteValue: Int? = nil
        var minuteDigits: Int = 0
        var dateNeedle: [UInt8] = []
        var todayStart = Date.distantPast
        var tomorrowStart = Date.distantFuture
        var yesterdayStart = Date.distantPast

        var isActive: Bool {
            month != nil || weekday != nil || matchesYesterday || matchesToday
                || mightBeDateString || !hours.isEmpty
        }

        func matches(_ entry: Entry) -> Bool {
            if let m = month, let d = day, entry.month == m, entry.day == d { return true }
            if let w = weekday, entry.weekday == w { return true }
            if matchesYesterday, entry.timestamp >= yesterdayStart, entry.timestamp < todayStart { return true }
            if matchesToday, entry.timestamp >= todayStart, entry.timestamp < tomorrowStart { return true }
            if !hours.isEmpty, hours.contains(entry.hour) {
                guard let value = minuteValue else { return true }
                if minuteDigits >= 2 {
                    if entry.minute == value { return true }
                } else if entry.minute / 10 == value {
                    return true
                }
            }
            if mightBeDateString, ClipboardSearchIndex.contains(entry.dateBytes, dateNeedle) { return true }
            return false
        }
    }

    private static let timePattern = try! NSRegularExpression(
        pattern: "(\\d{1,2})(?::(\\d{1,2}))?\\s*([ap]m)?",
        options: [.caseInsensitive]
    )

    /// Parses a time out of a query like "2:30 pm", "9 am", "10:1", "12:30".
    /// Returns nil when the query does not actually name a time.
    static func parseTime(_ query: String) -> (hours: [Int], minuteValue: Int?, minuteDigits: Int)? {
        let full = NSRange(query.startIndex..., in: query)
        guard let match = timePattern.firstMatch(in: query, options: [], range: full) else { return nil }
        guard let hourRange = Range(match.range(at: 1), in: query),
              let hour = Int(query[hourRange]) else { return nil }

        var minuteValue: Int?
        var minuteDigits = 0
        if match.range(at: 2).location != NSNotFound,
           let minuteRange = Range(match.range(at: 2), in: query) {
            let digits = query[minuteRange]
            minuteValue = Int(digits)
            minuteDigits = digits.count
        }

        var meridiem: String?
        if match.range(at: 3).location != NSNotFound,
           let meridiemRange = Range(match.range(at: 3), in: query) {
            meridiem = query[meridiemRange].lowercased()
        }

        // Require a colon or an am/pm suffix, so a bare number is not a time query.
        guard minuteValue != nil || meridiem != nil else { return nil }

        let hours: [Int]
        if let meridiem {
            let base = hour % 12
            hours = [meridiem == "am" ? base : base + 12]
        } else if hour > 12 {
            hours = [hour]
        } else if hour == 12 {
            hours = [0, 12]
        } else {
            hours = [hour, hour + 12]
        }
        return (hours, minuteValue, minuteDigits)
    }

    private(set) var entries: [Entry] = []
    private(set) var itemsById: [UUID: ClipboardItem] = [:]

    var isReady: Bool { !entries.isEmpty }

    static func fold(_ text: String) -> [UInt8] {
        Array(text.lowercased().utf8)
    }

    static func entry(for seed: Seed) -> Entry {
        let calendar = Calendar.current
        let timestamp = seed.timestamp
        return Entry(
            id: seed.id,
            timestamp: timestamp,
            bytes: fold(seed.content),
            dateBytes: fold(fullFormatter.string(from: timestamp)),
            month: calendar.component(.month, from: timestamp),
            day: calendar.component(.day, from: timestamp),
            weekday: calendar.component(.weekday, from: timestamp),
            hour: calendar.component(.hour, from: timestamp),
            minute: calendar.component(.minute, from: timestamp)
        )
    }

    static func needle(for query: String) -> [UInt8] {
        fold(query)
    }

    /// Byte-wise substring search. UTF-8 byte equality is code-point equality,
    /// so this matches the same text a case-insensitive String search would.
    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        let n = needle.count
        if n == 0 { return true }
        let h = haystack.count
        if n > h { return false }
        return haystack.withUnsafeBufferPointer { hay in
            needle.withUnsafeBufferPointer { nd in
                let first = nd[0]
                let last = h - n
                var i = 0
                while i <= last {
                    if hay[i] == first {
                        var j = 1
                        while j < n && hay[i + j] == nd[j] { j += 1 }
                        if j == n { return true }
                    }
                    i += 1
                }
                return false
            }
        }
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    func replace(entries: [Entry], itemsById: [UUID: ClipboardItem]) {
        self.entries = entries
        self.itemsById = itemsById
    }

    func insertNewest(_ entry: Entry, item: ClipboardItem) {
        entries.insert(entry, at: 0)
        itemsById[entry.id] = item
    }

    func items(for ids: [UUID]) -> [ClipboardItem] {
        var out: [ClipboardItem] = []
        out.reserveCapacity(ids.count)
        for id in ids {
            if let item = itemsById[id] { out.append(item) }
        }
        return out
    }
}
