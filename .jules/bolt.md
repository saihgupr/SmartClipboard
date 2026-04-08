## 2024-04-06 - Date Formatting inside loops

**Learning:** DateFormatter and Calendar operations are notoriously slow in Swift and should be avoided inside hot loops like search filter closures. Doing `.string(from: date)` or `.dateComponents(...)` per item when a query does not look like a date or time wastes cycles and creates unintended fuzzy matches.
**Action:** Extract invariant string checks outside of loops. Add "fast-path" early-return checks (e.g. `mightBeTimeOrDate` checking for digits/symbols) to bypass expensive formatting if the input doesn't warrant it.

## 2024-05-19 - Expensive Calendar ops in SwiftUI ForEach

**Learning:** Calling `Calendar.current.isDateInToday` or similar calendar operations directly inside a SwiftUI `ForEach` rendering loop causes significant performance bottlenecks, especially with large lists, as it forces date component calculations per item per render cycle.
**Action:** Always pre-compute date boundaries outside of the render loop (e.g. `todayStart`, `tomorrowStart`) and use direct `Date` comparisons (`date >= todayStart && date < tomorrowStart`), passing them to child views or formatting functions.
