#!/bin/bash
set -euo pipefail
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OUT="output/NextAuraCoreBridge.bundle"
NAME="NextAuraCoreBridge"
mkdir -p "$OUT" output/thin

for ARCH in arm64 arm64e; do
  xcrun --sdk iphoneos clang \
    -arch "$ARCH" -isysroot "$SDK" -miphoneos-version-min=16.0 \
    -fobjc-arc -Os -dynamiclib \
    -framework Foundation -framework UIKit \
    -Wl,-undefined,dynamic_lookup -Wl,-adhoc_codesign \
    -Wl,-install_name,@rpath/${NAME} \
    nextaura-test23/CoreBridge.m -o "output/thin/${NAME}.${ARCH}"
done

xcrun lipo -create "output/thin/${NAME}.arm64" "output/thin/${NAME}.arm64e" -output "$OUT/$NAME"
cat > "$OUT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>English</string>
  <key>CFBundleExecutable</key><string>NextAuraCoreBridge</string>
  <key>CFBundleIdentifier</key><string>com.nextsolution.nextauracorebridge</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>NextAura Core Bridge</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>1.1</string>
  <key>NSPrincipalClass</key><string>NACoreBridgeController</string>
</dict>
</plist>
PLIST

xcrun lipo -info "$OUT/$NAME"
file "$OUT/$NAME"
codesign -dvv "$OUT/$NAME" 2>&1 || true
shasum -a 256 "$OUT/$NAME" > output/SHA256SUMS
