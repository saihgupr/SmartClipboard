#!/bin/bash

# deploy.sh - SmartClipboard Build & Install Script

BUNDLE_ID="com.chrislapointe.SmartClipboard"
APP_PATH="/Applications/SmartClipboard.app"
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"

# 1. Generate Xcode project
echo "🔄 Generating Xcode project..."
xcodegen generate

# 2. Kill existing instance
echo "🔪 Stopping current instance..."
killall SmartClipboard &>/dev/null || true

# 3. Build the app
echo "🏗️ Building SmartClipboard (Release) with Ad-Hoc signing..."
xcodebuild -scheme SmartClipboard -configuration Release -derivedDataPath ./build build CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE="Manual"

# 4. Install to /Applications
echo "📦 Installing to /Applications..."
rm -rf "$APP_PATH"
cp -R ./build/Build/Products/Release/SmartClipboard.app "$APP_PATH"

# 5. Sign the app with a stable ad-hoc identity
echo "🖋️ Re-signing binary for TCC persistence..."
codesign --force --deep --sign - "$APP_PATH"

# 6. Grant Accessibility permission (dev convenience — avoids manual approval each build)
echo "🔐 Granting Accessibility permission..."
if [ -f "$TCC_DB" ]; then
    # We clear the existing entry first then re-add to avoid stale cache issues
    sudo sqlite3 "$TCC_DB" "DELETE FROM access WHERE client='$BUNDLE_ID' AND service='kTCCServiceAccessibility';" 2>/dev/null
    sudo sqlite3 "$TCC_DB" "INSERT INTO access \
        (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, flags, last_modified) \
        VALUES ('kTCCServiceAccessibility', '$BUNDLE_ID', 0, 2, 4, 1, 'UNUSED', 0, strftime('%s','now'));" 2>/dev/null && \
        echo "   ✅ Accessibility granted" || \
        echo "   ⚠️  Could not auto-grant (Full Disk Access required for Terminal). Grant manually once in System Settings."
else
    echo "   ⚠️  TCC database not found at expected path: $TCC_DB"
fi

# 7. Launch
echo "🚀 Launching SmartClipboard..."
open "$APP_PATH"

echo "✅ Deployment complete!"
