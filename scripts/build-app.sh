#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/ClipFlow.app"
CONTENTS="$APP/Contents"
ICONSET="$ROOT/.build/ClipFlow.iconset"

cd "$ROOT"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP" "$ICONSET"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ICONSET"

cp "$BIN_DIR/ClipFlow" "$CONTENTS/MacOS/ClipFlow"
lipo -verify_arch arm64 x86_64 "$CONTENTS/MacOS/ClipFlow"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$ROOT/Resources/AppIcon.svg" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -s format png -z "$double" "$double" "$ROOT/Resources/AppIcon.svg" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
