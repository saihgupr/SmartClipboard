# Changelog

All notable changes to this project will be documented in this file.

## [1.0.2] - 2026-07-10

### Added
- Integrated native macOS 26.0+ Liquid Glass (`NSGlassEffectView`) for the window and detail view backgrounds when running on macOS 26.0 or later.

### Fixed
- Resolved visual artifact in the menu bar popover where a straight horizontal line cut across the pointer arrow beak. Used native `NSPopover` glass frame rendering by utilizing transparent view backgrounds when displayed inside a popover.

## [1.0.1] - 2026-07-07

### Added
- Initial release of SmartClipboard.
- Features included AI semantic search (Gemini integration), global shortcuts, sequential pasting, incognito mode, favorites/pins, and clipboard history migrations.
