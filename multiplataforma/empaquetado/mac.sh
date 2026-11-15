#!/bin/bash
# Monta Proyectapp.app con el motor VLC nativo dentro y crea su DMG.
# Uso: mac.sh arm64|x64   (arm64 = Mac con Apple Silicon; x64 = Mac con Intel)
set -euo pipefail
cd "$(dirname "$0")/.."
ARQ="${1:-arm64}"
VLC_VERSION="3.0.21"
if [ "$ARQ" = "arm64" ]; then VLC_DMG="vlc-$VLC_VERSION-arm64.dmg"; else VLC_DMG="vlc-$VLC_VERSION-intel64.dmg"; fi

APP="salida/Proyectapp.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R "salida/mac-$ARQ/." "$APP/Contents/MacOS/"

# Motor VLC oficial para esta arquitectura
mkdir -p salida/vlc
if [ ! -f "salida/vlc/$VLC_DMG" ]; then
  curl -fL --retry 4 --retry-delay 5 -o "salida/vlc/$VLC_DMG" "https://get.videolan.org/vlc/$VLC_VERSION/macosx/$VLC_DMG"
fi
MONTAJE="$(mktemp -d)"
hdiutil attach "salida/vlc/$VLC_DMG" -nobrowse -readonly -mountpoint "$MONTAJE" >/dev/null
mkdir -p "$APP/Contents/MacOS/vlc"
cp -R "$MONTAJE/VLC.app/Contents/MacOS/lib" "$APP/Contents/MacOS/vlc/lib"
cp -R "$MONTAJE/VLC.app/Contents/MacOS/plugins" "$APP/Contents/MacOS/vlc/plugins"
hdiutil detach "$MONTAJE" >/dev/null || true
# Módulos que una proyección no usa
rm -f "$APP/Contents/MacOS/vlc/plugins/"lib{stream_out,access_output,sap,upnp,bonjour,microdns,lua,macosx,minimal_macosx}*_plugin.dylib 2>/dev/null || true
ls "$APP/Contents/MacOS/vlc/lib" | head -5

ICONSET="salida/Icono.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" Recursos/icono-app.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); sips -z "$d" "$d" Recursos/icono-app.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns -o "$APP/Contents/Resources/Proyectapp.icns" "$ICONSET"; rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Proyectapp</string>
  <key>CFBundleIdentifier</key><string>org.muyuna.proyectapp</string>
  <key>CFBundleName</key><string>Proyectapp</string>
  <key>CFBundleDisplayName</key><string>Proyectapp</string>
  <key>CFBundleIconFile</key><string>Proyectapp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>${GITHUB_RUN_NUMBER:-1}</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>App desarrollada por Muyuna.org</string>
</dict></plist>
PLIST
chmod +x "$APP/Contents/MacOS/Proyectapp"
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"
du -sh "$APP"
if [ "$ARQ" = "arm64" ]; then DMG="salida/Proyectapp-Mac.dmg"; else DMG="salida/Proyectapp-Mac-Intel.dmg"; fi
rm -rf salida/dmg; mkdir -p salida/dmg && cp -R "$APP" salida/dmg/ && ln -s /Applications salida/dmg/Applications
hdiutil create -volname "Proyectapp" -srcfolder salida/dmg -ov -format UDZO "$DMG" >/dev/null
rm -rf salida/dmg
ls -lh "$DMG"
