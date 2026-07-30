#!/bin/bash
set -euo pipefail

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OUT="output"
NAME="NextIslandPrefs"

rm -rf "$OUT"
mkdir -p "$OUT/thin"

for ARCH in arm64 arm64e; do
  xcrun --sdk iphoneos clang \
    -arch "$ARCH" \
    -isysroot "$SDK" \
    -miphoneos-version-min=16.0 \
    -fobjc-arc -Os -bundle \
    -framework Foundation \
    -framework UIKit \
    -framework CoreFoundation \
    -F"$SDK/System/Library/PrivateFrameworks" \
    -framework Preferences \
    -Wl,-undefined,dynamic_lookup \
    next-island/NextIslandRootListController.m \
    -o "$OUT/thin/${NAME}.${ARCH}"
done

xcrun lipo -create \
  "$OUT/thin/${NAME}.arm64" \
  "$OUT/thin/${NAME}.arm64e" \
  -output "$OUT/$NAME"

chmod 0755 "$OUT/$NAME"
codesign --force --sign - --timestamp=none "$OUT/$NAME"

xcrun lipo -info "$OUT/$NAME"
file "$OUT/$NAME"
codesign --verify --strict --verbose=2 "$OUT/$NAME"
strings "$OUT/$NAME" | grep -q 'NextIslandRootListController'
strings "$OUT/$NAME" | grep -q 'com.nextsolution.unlockvibrate/test-dynamic-island-suite'
shasum -a 256 "$OUT/$NAME" > "$OUT/SHA256SUMS"
