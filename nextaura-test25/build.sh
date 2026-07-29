#!/bin/bash
set -euo pipefail
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
NAME="ZZNextAuraDirectCoreLoader"
OUT="output"
rm -rf "$OUT"
mkdir -p "$OUT/thin"

for ARCH in arm64 arm64e; do
  xcrun --sdk iphoneos clang \
    -arch "$ARCH" -isysroot "$SDK" -miphoneos-version-min=16.0 \
    -fobjc-arc -Os -dynamiclib \
    -framework Foundation -framework UIKit \
    -Wl,-undefined,dynamic_lookup \
    -Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/${NAME}.dylib \
    nextaura-test25/DirectWorkingCoreLoader.m \
    -o "$OUT/thin/${NAME}.${ARCH}.dylib"
done

xcrun lipo -create \
  "$OUT/thin/${NAME}.arm64.dylib" \
  "$OUT/thin/${NAME}.arm64e.dylib" \
  -output "$OUT/${NAME}.dylib"

chmod 0755 "$OUT/${NAME}.dylib"
codesign --force --sign - --timestamp=none "$OUT/${NAME}.dylib"

xcrun lipo -info "$OUT/${NAME}.dylib"
file "$OUT/${NAME}.dylib"
codesign --verify --strict --verbose=2 "$OUT/${NAME}.dylib"
strings "$OUT/${NAME}.dylib" | grep -q 'openNextAuraWorkingCoreDirect:'
strings "$OUT/${NAME}.dylib" | grep -q 'STPreferences.bundle'
shasum -a 256 "$OUT/${NAME}.dylib" > "$OUT/SHA256SUMS"
