## 2024-04-06 - Date Formatting inside loops

**Learning:** DateFormatter and Calendar operations are notoriously slow in Swift and should be avoided inside hot loops like search filter closures. Doing `.string(from: date)` or `.dateComponents(...)` per item when a query does not look like a date or time wastes cycles and creates unintended fuzzy matches.
**Action:** Extract invariant string checks outside of loops. Add "fast-path" early-return checks (e.g. `mightBeTimeOrDate` checking for digits/symbols) to bypass expensive formatting if the input doesn't warrant it.

## 2024-05-19 - Expensive Calendar ops in SwiftUI ForEach

**Learning:** Calling `Calendar.current.isDateInToday` or similar calendar operations directly inside a SwiftUI `ForEach` rendering loop causes significant performance bottlenecks, especially with large lists, as it forces date component calculations per item per render cycle.
**Action:** Always pre-compute date boundaries outside of the render loop (e.g. `todayStart`, `tomorrowStart`) and use direct `Date` comparisons (`date >= todayStart && date < tomorrowStart`), passing them to child views or formatting functions.

## 2024-04-10 - DateFormatter Cache Invalidation in Loops

**Learning:** Mutating a `DateFormatter`'s `dateFormat` property repeatedly inside a loop invalidates its internal ICU cache, multiplying the performance penalty of formatting. Furthermore, fetching calendar symbol arrays inside loops causes continuous allocations.
**Action:** Extract formatters into statically allocated arrays, pre-configuring each with its required format. Extract calendar symbol arrays into static properties.

## 2024-05-24 - Overly broad fast-paths causing O(N) operations

**Learning:** Implementing "fast-paths" that are too broad (e.g., checking if a query string contains ANY digits to determine if it MIGHT be a date) can have disastrous performance implications. In a local search filter, a query like "bug 123" triggered expensive O(N) `DateFormatter` calculations on every single item in history, destroying search responsiveness.
**Action:** Fast-path conditional flags must be strict. When attempting to bypass expensive formatting inside a loop, ensure the check is highly specific (e.g., requires specific date delimiters like `:`, `/`, `-`, or explicit month/weekday match) rather than a generic digit check.

## 2024-05-18 - Avoid DateComponents allocations in tight Swift loops
**Learning:** Extracting multiple components using `Calendar.current.dateComponents` inside an unbounded `filter` loop allocates a heavy struct and destroys performance. Additionally, pre-computing large date arrays to avoid this can cause O(N*M) regressions.
**Action:** Use scalar `calendar.component(_:from:)` calls for individual integers instead, as it avoids struct allocations entirely.
