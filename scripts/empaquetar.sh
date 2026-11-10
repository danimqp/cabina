#!/bin/bash
# Compila Cabina, monta Cabina.app y crea Cabina.dmg dentro de build/.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0}"
BUILD="${GITHUB_RUN_NUMBER:-1}"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Cabina"

rm -rf build
APP="build/Cabina.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cabina"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Recursos/Info.plist > "$APP/Contents/Info.plist"

ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" Recursos/icono.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" Recursos/icono.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$ICONSET"

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Cabina"

DMG_DIR="build/dmg"
mkdir -p "$DMG_DIR"
cp -R "$APP" "$DMG_DIR/"
cp Recursos/LEEME.txt "$DMG_DIR/LÉEME.txt"
ln -s /Applications "$DMG_DIR/Applications"
hdiutil create -volname "Cabina" -srcfolder "$DMG_DIR" -ov -format UDZO build/Cabina.dmg >/dev/null
rm -rf "$DMG_DIR"
ls -lh build/Cabina.dmg
