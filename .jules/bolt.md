## 2024-04-06 - Date Formatting inside loops

**Learning:** DateFormatter and Calendar operations are notoriously slow in Swift and should be avoided inside hot loops like search filter closures. Doing `.string(from: date)` or `.dateComponents(...)` per item when a query does not look like a date or time wastes cycles and creates unintended fuzzy matches.
**Action:** Extract invariant string checks outside of loops. Add "fast-path" early-return checks (e.g. `mightBeTimeOrDate` checking for digits/symbols) to bypass expensive formatting if the input doesn't warrant it.
