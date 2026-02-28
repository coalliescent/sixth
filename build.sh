#!/bin/bash
set -e

cd "$(dirname "$0")"

BUNDLE="Sixth.app"
BUNDLE_ID="com.sixth.pandora"
SIGN_ID="Sixth Dev"

echo "Building Sixth..."

# Compile binary
swiftc -parse-as-library \
  -framework AppKit -framework AVFoundation -framework Carbon \
  -framework Security -framework Network -framework UserNotifications \
  -swift-version 5 -o Sixth Sources/*.swift

# Create .app bundle
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
mv Sixth "$BUNDLE/Contents/MacOS/Sixth"
cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>
  <string>Sixth</string>
  <key>CFBundleExecutable</key>
  <string>Sixth</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

# Sign the bundle
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  codesign --force --sign "$SIGN_ID" "$BUNDLE" 2>&1
  echo "Built + signed: ./$BUNDLE"
else
  echo "Built: ./$BUNDLE (unsigned — '$SIGN_ID' identity not found)"
fi

# Build tests
echo "Building tests..."
swiftc -parse-as-library -DTESTING \
  -swift-version 5 -o SixthTests \
  Sources/Models.swift Sources/BlowfishCrypto.swift Sources/PandoraAPI.swift \
  Sources/CredentialStore.swift Sources/AudioPlayer.swift \
  Tests/*.swift

echo "Built: ./SixthTests"

# Build credential helper (only when source is newer)
if [ ! -f sixth-creds ] || [ Tools/sixth-creds.swift -nt sixth-creds ]; then
  echo "Building sixth-creds..."
  swiftc -swift-version 5 -o sixth-creds Tools/sixth-creds.swift
fi

echo "Done!"
