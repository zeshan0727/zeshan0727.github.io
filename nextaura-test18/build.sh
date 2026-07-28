#!/bin/bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import base64, gzip
encoded = Path('nextaura-test18/LockScreenStyler.m.gz.b64').read_text().strip()
Path('nextaura-test18/LockScreenStyler.m').write_bytes(gzip.decompress(base64.b64decode(encoded)))
PY
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p output
NAME="ZZNextAuraLockScreenStyler"
for ARCH in arm64 arm64e; do
  xcrun --sdk iphoneos clang \
    -arch "$ARCH" -isysroot "$SDK" -miphoneos-version-min=16.0 \
    -fobjc-arc -Os -dynamiclib \
    -framework Foundation -framework UIKit -framework QuartzCore \
    -Wl,-undefined,dynamic_lookup -Wl,-adhoc_codesign \
    -Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/${NAME}.dylib \
    nextaura-test18/LockScreenStyler.m -o "output/${NAME}.${ARCH}.dylib"
done
xcrun lipo -create "output/${NAME}.arm64.dylib" "output/${NAME}.arm64e.dylib" -output "output/${NAME}.dylib"
rm "output/${NAME}.arm64.dylib" "output/${NAME}.arm64e.dylib"
xcrun lipo -info "output/${NAME}.dylib"
file "output/${NAME}.dylib"
codesign -dvv "output/${NAME}.dylib" 2>&1 || true
shasum -a 256 "output/${NAME}.dylib" > output/SHA256SUMS
