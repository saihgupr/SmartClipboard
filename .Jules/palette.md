## 2024-04-10 - Disable Disabled States Frustration
**Learning:** Empty states in search-heavy applications should distinguish between an overall empty dataset and a search yielding zero results, providing specific calls to action for each scenario. Additionally, disabling buttons (like API tests) without providing a tooltip (`.help()`) explaining why they are disabled causes user frustration.
**Action:** When creating empty states, ensure context-specific actionable items are available (e.g., "Clear Search" button). When disabling an interactive element, always provide a tooltip explaining the requirement.## 2026-04-11 - [Empty State CTA]
**Learning:** Empty states with instructional text but no inline Call to Action are frustrating.
**Action:** Always ensure empty states include a prominent button or control for the user to immediately take the action described in the text.
## 2024-05-17 - Actionable Empty States and Contextual Tooltips
**Learning:** Adding a CTA (like a "Clear Search" button) inside an empty state ensures users don't get stuck and provides an immediate recovery path. Furthermore, providing explicit tooltips to explain why elements are disabled avoids user confusion and frustration.
**Action:** Always provide an actionable reset step in empty search states, and always use `.help()` to explain the condition that disabled an interactive element.
