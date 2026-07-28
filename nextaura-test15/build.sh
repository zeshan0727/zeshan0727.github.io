#!/bin/bash
set -euo pipefail
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p output

# PSListController's private table accessor is invoked through KVC so ARC can
# compile the preview without requiring private Preference headers.
python3 - <<'PY'
from pathlib import Path
p = Path('nextaura-test15/Preview.m')
s = p.read_text()
s = s.replace('table = [controller table];', 'table = [controller valueForKey:@"table"];')
p.write_text(s)
PY

build_universal() {
  local SRC="$1" NAME="$2"
  echo "Compiling $NAME"
  for ARCH in arm64 arm64e; do
    echo "Architecture: $ARCH"
    xcrun --sdk iphoneos clang -arch "$ARCH" -isysroot "$SDK" -miphoneos-version-min=16.0 \
      -fobjc-arc -Os -dynamiclib -framework Foundation -framework UIKit -framework QuartzCore \
      -Wl,-undefined,dynamic_lookup -Wl,-adhoc_codesign \
      -Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/${NAME}.dylib \
      "$SRC" -o "output/${NAME}.${ARCH}.dylib"
  done
  xcrun lipo -create "output/${NAME}.arm64.dylib" "output/${NAME}.arm64e.dylib" -output "output/${NAME}.dylib"
  rm "output/${NAME}.arm64.dylib" "output/${NAME}.arm64e.dylib"
  xcrun lipo -info "output/${NAME}.dylib"
  codesign -dvv "output/${NAME}.dylib" 2>&1 || true
}
build_universal nextaura-test15/OpeningGuardV3.m ZZNextAuraSwitcherOpeningGuard
build_universal nextaura-test15/Preview.m ZZNextAuraSwitcherPreview
shasum -a 256 output/*.dylib > output/SHA256SUMS
