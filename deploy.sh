#!/bin/bash
set -e

# deploy.sh - SmartClipboard Build & Install Script

# Load local environment overrides if present
if [ -f .env ]; then
    echo "🔑 Loading environment overrides from .env..."
    source .env
fi

BUNDLE_ID="${SMARTCLIPBOARD_BUNDLE_ID:-com.saihgupr.SmartClipboard}"
APP_PATH="/Applications/SmartClipboard.app"

# Identify signing identity — prefer a stable Apple Development cert so
# macOS doesn't revoke accessibility/automation permissions on each build.
SIGN_IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '{print $2}' | head -1 || true)
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="-"
    echo "⚠️  No codesigning identity found — using ad-hoc signing (-)"
    USING_ADHOC=true
else
    echo "🔏 Using stable signing identity: $SIGN_IDENTITY"
    USING_ADHOC=false
fi

# 1. Generate Xcode project
echo "🔄 Generating Xcode project..."
xcodegen generate

# 2. Kill existing instance
echo "🔪 Stopping current instance..."
killall SmartClipboard &>/dev/null || true

# 3. Run unit tests (skip with SKIP_TESTS=1)
if [ "${SKIP_TESTS:-0}" != "1" ]; then
    echo "🧪 Running unit tests..."
    TEST_LOG=$(mktemp)
    if ! xcodebuild test -scheme SmartClipboard -destination 'platform=macOS' -derivedDataPath ./build \
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
        CODE_SIGN_STYLE="Manual" \
        DEVELOPMENT_TEAM="" > "$TEST_LOG" 2>&1; then
        echo "❌ Tests failed:"
        grep -E "error:|failed \(" "$TEST_LOG" | head -20
        rm -f "$TEST_LOG"
        exit 1
    fi
    grep -E "Executed [0-9]+ tests" "$TEST_LOG" | tail -1
    rm -f "$TEST_LOG"
else
    echo "⏭️  Skipping tests (SKIP_TESTS=1)"
fi

# 4. Build the app
echo "🏗️ Building SmartClipboard (Release)..."
xcodebuild -scheme SmartClipboard -configuration Release -derivedDataPath ./build build \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE="Manual" \
    DEVELOPMENT_TEAM="" 2>&1 | tail -3

# 5. Install to /Applications
echo "📦 Installing to /Applications..."
rm -rf "$APP_PATH"
cp -R ./build/Build/Products/Release/SmartClipboard.app "$APP_PATH"

# 6. Sign with stable identity
echo "🖋️  Re-signing binary..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"

# 7. Only reset TCC when using ad-hoc (stable identity preserves permissions)
if [ "$USING_ADHOC" = true ]; then
    echo "🔐 Resetting accessibility entry (ad-hoc build changes hash)..."
    tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
else
    echo "✅ Stable identity — skipping TCC reset (permissions preserved)"
fi

# 8. Refresh icon cache
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
    -f -r "$APP_PATH"
touch "$APP_PATH"

# 9. Launch
echo "🚀 Launching SmartClipboard..."
open "$APP_PATH"

echo "✅ Deployment complete!"
