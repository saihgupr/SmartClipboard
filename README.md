# 📋 SmartClipboard

SmartClipboard is a modern macOS menu bar application built with SwiftUI that enhances your clipboard experience with AI-powered semantic search.

![SmartClipboard Icon](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![Gemini](https://img.shields.io/badge/AI-Gemini_1.5_Flash-purple.svg)

## ✨ Features

- **🚀 Always Accessible**: Lives in your macOS menu bar for quick access anytime.
- **🧠 Semantic Search**: Don't just search for keywords. Ask questions like "Where was that API key?" or "Find that snippet about database migrations" using the power of Gemini 1.5 Flash.
- **🕒 Clipboard History**: Automatically tracks and stores your last 100 clipboard items.
- **🖱️ Visual History**: A clean, monospaced list view showing timestamps and content snippets.
- **🔄 Quick Restore**: Click any item in the history to instantly copy it back to your system clipboard.

## 🛠️ Technology Stack

- **SwiftUI**: For the modern, responsive user interface.
- **AppKit**: Utilizes `NSPasteboard` for reliable clipboard monitoring.
- **Gemini API**: Integrates Google's Gemini 1.5 Flash model for intelligent semantic analysis of your history.
- **XcodeGen**: Project management via `project.yml` for clean version control.

## 🚀 Getting Started

### Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- A Gemini API Key (already configured in the project)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/chrislapointe/SmartClipboard.git
   cd SmartClipboard
   ```

2. Generate the Xcode project (if you have XcodeGen installed):
   ```bash
   xcodegen generate
   ```

3. Open `SmartClipboard.xcodeproj` in Xcode.

4. Build and run the project (Cmd + R).

## 📖 Usage

- **Monitoring**: The app automatically starts polling the clipboard every second once launched.
- **Searching**: Use the search bar in the popover to ask AI to find specific items in your history.
- **Copying**: Click on any item in the list to re-copy it to your clipboard.

---

*Built with ❤️ by Chris LaPointe*
