#!/bin/bash

# deploy.sh - SmartClipboard Build & Install Script

# 1. Generate Xcode project
echo "🔄 Generating Xcode project..."
xcodegen generate

# 2. Kill existing instance
echo "🔪 Stopping current instance..."
killall SmartClipboard &>/dev/null || true

# 3. Build the app
echo "🏗️ Building SmartClipboard (Release)..."
xcodebuild -scheme SmartClipboard -configuration Release -derivedDataPath ./build build

# 4. Install to /Applications
echo "📦 Installing to /Applications..."
rm -rf /Applications/SmartClipboard.app
cp -R ./build/Build/Products/Release/SmartClipboard.app /Applications/

# 5. Launch
echo "🚀 Launching SmartClipboard..."
open /Applications/SmartClipboard.app

echo "✅ Deployment complete!"
