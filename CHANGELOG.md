# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Copy on Select: optional terminal-style highlight-to-copy. Highlighting text in any app copies it to the clipboard automatically. Off by default; enable in Settings → General → Auto-Copy. Skips password fields and SmartClipboard's own windows. Smart about drags: the highlight must settle briefly before copying (no mid-drag spam), and extending a just-copied selection merges into the same history entry instead of adding a near-duplicate.

### Fixed
- Copy on Select no longer clobbers explicit copies: when the clipboard changes externally (e.g. Cmd+C of Keyboard Maestro actions), that copy wins and the still-highlighted text is suppressed until the highlight actually changes. The Chromium accessibility opt-in is now only attempted for Chromium/Electron apps, so ordinary AppKit apps are never touched.
- Copy on Select now works in Chromium-based browsers and Electron apps such as Dia, Chrome, and VS Code. Those apps keep their accessibility tree disabled until a client opts in, so SmartClipboard now sets `AXManualAccessibility` on the frontmost app and falls back to text-marker and selected-range attributes when `AXSelectedText` is unavailable. Selecting the same text again also copies it when the clipboard has changed since the last copy.
- Fixed Theme Style settings row where the segmented picker overlapped the description text.
- Show main panel above floating mini-windows (e.g. Gemini small-talk overlay) and paste directly to the previous app via postToPid so paste lands in non-activating floaters.
- Open the main panel as a non-activating panel so the Gemini mini popup stays visible while picking an item.
- Search now runs against a pre-folded byte index: ~5 ms per keystroke on a 15k-item history instead of ~65 ms. Date and time queries ("today", "2:30 pm", "07/13") parse once and compare precomputed fields instead of formatting every timestamp. Pasting no longer waits on a SwiftData save, and global hotkey pastes fetch only the requested row instead of the whole history.
- Arrow-key navigation no longer re-filters the entire clipboard history on every keypress; the filtered and paginated lists are cached and rebuilt only when history, query, pins, or deletions change.

### Changed
- Snippets now appear only when the search starts with `/`. Typing plain text no longer surfaces slash commands such as `/fixbugs`.

## [1.0.5] - 2026-07-18

### Changed
- Increased Dark Glass theme background opacity to make it darker and more refined.
- Removed a horizontal divider line in the main status bar popup window.

## [1.0.4] - 2026-07-13

### Changed
- Replaced the native `NSPopover` with a custom floating panel positioned relative to the menu bar status item. This enables consistent themes, seamless visual transitions, and custom styling for the popover interface.
- Updated the features presentation in `README.md` to highlight key capabilities (AI Search, Date & Time finding, Dual Access Layouts, Keyboard Shortcuts, and Migration).

## [1.0.3] - 2026-07-13

### Added
- Introduced the **Dark Glass** theme style option using macOS 26.0+'s clear Liquid Glass (`NSGlassEffectView.Style.clear`) with native dark tinting (`tintColor`). This gives a clear, refractive physical glass look (distorted warp) without frosted blur.
- Set **Dark Glass** as the default app theme style.
- Enhanced specular gradients and outer border stroke opacities on both Glass and Dark Glass themes to make reflection highlights look crisper and more physical.
- Updated the **Left Arrow Key** action logic to automatically copy the item to the clipboard and update its timestamp to move it to the top of the history list for all actions (except delete).

### Fixed
- Fixed a bug in `deploy.sh` that was incorrectly checking runner permissions and wiping out the application's macOS Accessibility permissions on every deployment.

## [1.0.2] - 2026-07-10

### Added
- Integrated native macOS 26.0+ Liquid Glass (`NSGlassEffectView`) for the window and detail view backgrounds when running on macOS 26.0 or later.

### Fixed
- Resolved visual artifact in the menu bar popover where a straight horizontal line cut across the pointer arrow beak. Used native `NSPopover` glass frame rendering by utilizing transparent view backgrounds when displayed inside a popover.

## [1.0.1] - 2026-07-07

### Added
- Initial release of SmartClipboard.
- Features included AI semantic search (Gemini integration), global shortcuts, sequential pasting, incognito mode, favorites/pins, and clipboard history migrations.
