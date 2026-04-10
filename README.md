# 📋 SmartClipboard

SmartClipboard is a modern macOS menu bar application built with SwiftUI that enhances your clipboard experience with AI-powered semantic search.

![macOS 13.0+](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)
![Gemini 1.5 Flash](https://img.shields.io/badge/AI-Gemini_1.5_Flash-purple.svg)

## ✨ Features

- **🚀 Always Accessible**: Lives in your macOS menu bar for quick access anytime.
- **🔳 Dual UI Modes**: Triggering the app from the menu bar opens a focused popover, while using the global hotkey reveals a **center-screen floating window** (Spotlight-style).
- **⌨️ Global Shortcut**: Get instant access with a customizable global hotkey configured in Settings.
- **🧠 Semantic Search**: Ask natural language questions like "Where was that API key?" or "Find that snippet about database migrations" using Gemini 1.5 Pro or Flash.
- **⚡ High Performance**: Ultra-fast local search and history filtering, optimized for near-zero latency even with large history datasets.
- **🛡️ Privacy & Security**: Automatically filters sensitive data from password managers (1Password, Keychain). Uses safe URL construction and respects transient/concealed pasteboard flags.
- **🎨 Actionable UX**: Intuitive empty states and clear tooltips ensure you're never stuck without knowing what to do next.
- **🔄 Quick Restore**: Click any item or use keyboard shortcuts (Cmd+1-0) to instantly paste content back to your system clipboard.

## 🛠️ Technology Stack

- **SwiftUI**: For a native, modern macOS user interface.
- **AppKit**: Efficient clipboard monitoring via `NSPasteboard`.
- **SwiftData**: Modern, high-performance persistence layer for your history.
- **Gemini API**: Deep integration with Google's Gemini models for intelligent semantic analysis.
- **XcodeGen**: Clean project management and version control.

## 🚀 Getting Started

### Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- A [Google Gemini API Key](https://aistudio.google.com/app/apikey)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/chrislapointe/SmartClipboard.git
   cd SmartClipboard
   ```

2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

3. Build and run the project (Cmd + R) or use the included `deploy.sh` script for rapid installation to `/Applications`.

4. Provide your Gemini API key in the app settings to enable semantic search features.

---

*Built with ❤️ by Chris LaPointe*
