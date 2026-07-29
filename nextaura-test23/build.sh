#!/bin/bash
set -euo pipefail
# Test 24 rebuild trigger: true signed MH_BUNDLE.
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OUT="output/NextAuraCoreBridge.bundle"
NAME="NextAuraCoreBridge"
rm -rf output
mkdir -p "$OUT" output/thin

for ARCH in arm64 arm64e; do
  xcrun --sdk iphoneos clang \
    -arch "$ARCH" -isysroot "$SDK" -miphoneos-version-min=16.0 \
    -fobjc-arc -Os -bundle \
    -framework Foundation -framework UIKit \
    -Wl,-undefined,dynamic_lookup \
    nextaura-test23/CoreBridge.m -o "output/thin/${NAME}.${ARCH}"
done

xcrun lipo -create "output/thin/${NAME}.arm64" "output/thin/${NAME}.arm64e" -output "$OUT/$NAME"
chmod 0755 "$OUT/$NAME"

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
  <key>CFBundleShortVersionString</key><string>1.2</string>
  <key>CFBundleVersion</key><string>1.2</string>
  <key>NSPrincipalClass</key><string>NACoreBridgeController</string>
</dict>
</plist>
PLIST

# Sign the final universal bundle after lipo so Settings can load it.
codesign --force --sign - --timestamp=none "$OUT"

xcrun lipo -info "$OUT/$NAME"
file "$OUT/$NAME"
HEADER="$(xcrun llvm-objdump --macho --private-header "$OUT/$NAME")"
echo "$HEADER"
echo "$HEADER" | grep -q 'BUNDLE' || { echo 'ERROR: bridge is not MH_BUNDLE'; exit 1; }
codesign --verify --deep --strict --verbose=2 "$OUT"
codesign -dvv "$OUT" 2>&1 || true
shasum -a 256 "$OUT/$NAME" > output/SHA256SUMS
