#!/bin/bash

# deploy.sh - SmartClipboard Build & Install Script

# Load local environment overrides if present
if [ -f .env ]; then
    echo "🔑 Loading environment overrides from .env..."
    source .env
fi

BUNDLE_ID="${SMARTCLIPBOARD_BUNDLE_ID:-com.saihgupr.SmartClipboard}"
APP_PATH="/Applications/SmartClipboard.app"
SIGN_IDENTITY="${SMARTCLIPBOARD_SIGN_IDENTITY:--}"

# 1. Generate Xcode project
echo "🔄 Generating Xcode project..."
xcodegen generate

# 2. Kill existing instance
echo "🔪 Stopping current instance..."
killall SmartClipboard &>/dev/null || true

# 3. Build the app
echo "🏗️ Building SmartClipboard (Release)..."
xcodebuild -scheme SmartClipboard -configuration Release -derivedDataPath ./build build \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE="Manual" \
    DEVELOPMENT_TEAM="" 2>&1 | tail -3

# 4. Install to /Applications
echo "📦 Installing to /Applications..."
rm -rf "$APP_PATH"
cp -R ./build/Build/Products/Release/SmartClipboard.app "$APP_PATH"

# 5. Sign the app with a stable ad-hoc identity
echo "🖋️ Re-signing binary with stable identity..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"

# 6. Verify Accessibility permission
echo "🔐 Checking Accessibility permission..."
# With a stable signing identity, TCC remembers the grant across rebuilds.
# Only need to grant manually once on first install.
if osascript -e 'tell application "System Events" to return name of first process' &>/dev/null; then
    echo "   ✅ Accessibility already granted (persisted via stable signing identity)"
else
    echo "   ⚠️  Accessibility not yet granted. Resetting stale entries and opening System Settings..."
    tccutil reset Accessibility com.saihgupr.SmartClipboard &>/dev/null || true
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
fi

# 7. Launch
echo "🚀 Launching SmartClipboard..."
open "$APP_PATH"

echo "✅ Deployment complete!"
