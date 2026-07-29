#!/bin/bash
set -euo pipefail
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
NAME="ZZNextAuraSTNativeBridge"
OUT="output-test29"
rm -rf "$OUT"
mkdir -p "$OUT/thin"

for ARCH in arm64 arm64e; do
  xcrun --sdk iphoneos clang \
    -arch "$ARCH" \
    -isysroot "$SDK" \
    -miphoneos-version-min=16.0 \
    -fobjc-arc -Os -dynamiclib \
    -framework Foundation \
    -framework CoreFoundation \
    -Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/${NAME}.dylib \
    nextaura-test29/STPreferenceBridge.m \
    -o "$OUT/thin/${NAME}.${ARCH}.dylib"
done

xcrun lipo -create \
  "$OUT/thin/${NAME}.arm64.dylib" \
  "$OUT/thin/${NAME}.arm64e.dylib" \
  -output "$OUT/${NAME}.dylib"

chmod 0755 "$OUT/${NAME}.dylib"
codesign --force --sign - --timestamp=none "$OUT/${NAME}.dylib"

cat > "$OUT/${NAME}.plist" <<'PLIST'
{
    Filter = {
        Bundles = ("com.apple.springboard");
        Executables = ("SpringBoard");
    };
}
PLIST

xcrun lipo -info "$OUT/${NAME}.dylib"
file "$OUT/${NAME}.dylib"
codesign --verify --strict --verbose=2 "$OUT/${NAME}.dylib"
strings "$OUT/${NAME}.dylib" | grep -q 'com.st5.settings.appswitcher'
strings "$OUT/${NAME}.dylib" | grep -q 'com.nextsolution.unlockvibrate/preferences.changed'
shasum -a 256 "$OUT/${NAME}.dylib" "$OUT/${NAME}.plist" > "$OUT/SHA256SUMS"
