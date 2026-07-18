# Changelog

All notable changes to this project will be documented in this file.

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
