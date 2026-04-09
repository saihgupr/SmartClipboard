## 2024-04-06 - Date Formatting inside loops

**Learning:** DateFormatter and Calendar operations are notoriously slow in Swift and should be avoided inside hot loops like search filter closures. Doing `.string(from: date)` or `.dateComponents(...)` per item when a query does not look like a date or time wastes cycles and creates unintended fuzzy matches.
**Action:** Extract invariant string checks outside of loops. Add "fast-path" early-return checks (e.g. `mightBeTimeOrDate` checking for digits/symbols) to bypass expensive formatting if the input doesn't warrant it.

## 2024-05-19 - Expensive Calendar ops in SwiftUI ForEach

**Learning:** Calling `Calendar.current.isDateInToday` or similar calendar operations directly inside a SwiftUI `ForEach` rendering loop causes significant performance bottlenecks, especially with large lists, as it forces date component calculations per item per render cycle.
**Action:** Always pre-compute date boundaries outside of the render loop (e.g. `todayStart`, `tomorrowStart`) and use direct `Date` comparisons (`date >= todayStart && date < tomorrowStart`), passing them to child views or formatting functions.
## 2024-04-09 - Calendar ops inside filters

**Learning:** Calculating `Calendar.dateComponents` and `Calendar.component` inside highly iterative functions like a `filter` mapping over thousands of history items is extremely expensive in Swift and causes noticeable UI lag when searching.
**Action:** Extract all `Calendar` date math out of the search loop. Iterate backward through time outside the loop to calculate boundaries of matching days `[(start: Date, end: Date)]`. Then, inside the `filter` loop, check if the item's date falls within any of the pre-computed bounds using fast, direct `Date` comparisons.
