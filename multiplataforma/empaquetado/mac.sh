#!/bin/bash
# Monta Cabina.app (Intel; en Apple Silicon corre con Rosetta) y su DMG a partir de la publicación de .NET.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="salida/Cabina VLC.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R salida/mac/. "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Cabina</string>
  <key>CFBundleIdentifier</key><string>com.danimqp.cabina.vlc</string>
  <key>CFBundleName</key><string>Cabina VLC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>${GITHUB_RUN_NUMBER:-1}</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>App desarrollada por Muyuna.org</string>
</dict></plist>
PLIST
chmod +x "$APP/Contents/MacOS/Cabina"
codesign --force --deep --sign - "$APP"
mkdir -p salida/dmg && cp -R "$APP" salida/dmg/ && ln -s /Applications salida/dmg/Applications
hdiutil create -volname "Cabina VLC" -srcfolder salida/dmg -ov -format UDZO salida/Cabina-VLC-Mac.dmg >/dev/null
rm -rf salida/dmg
ls -lh salida/Cabina-VLC-Mac.dmg
