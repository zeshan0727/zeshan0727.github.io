#!/bin/bash
set -euo pipefail
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p output
for ARCH in arm64 arm64e; do
  xcrun --sdk iphoneos clang \
    -arch "$ARCH" -isysroot "$SDK" -miphoneos-version-min=16.0 \
    -fobjc-arc -Os -dynamiclib \
    -framework Foundation -framework UIKit -framework QuartzCore \
    -Wl,-undefined,dynamic_lookup -Wl,-adhoc_codesign \
    -Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/ZZNextAuraSwitcherSmoothness.dylib \
    nextaura-test16/Smoothness.m -o "output/ZZNextAuraSwitcherSmoothness.${ARCH}.dylib"
done
xcrun lipo -create \
  output/ZZNextAuraSwitcherSmoothness.arm64.dylib \
  output/ZZNextAuraSwitcherSmoothness.arm64e.dylib \
  -output output/ZZNextAuraSwitcherSmoothness.dylib
rm output/ZZNextAuraSwitcherSmoothness.arm64.dylib output/ZZNextAuraSwitcherSmoothness.arm64e.dylib
xcrun lipo -info output/ZZNextAuraSwitcherSmoothness.dylib
codesign -dvv output/ZZNextAuraSwitcherSmoothness.dylib 2>&1
shasum -a 256 output/ZZNextAuraSwitcherSmoothness.dylib > output/SHA256SUMS
