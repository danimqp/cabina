#!/bin/bash
# Arranca la app recién compilada con un vídeo y una imagen de prueba y comprueba su informe.
set -uo pipefail
cd "$(dirname "$0")/.."

P="$PWD/build/prueba"
rm -rf "$P"; mkdir -p "$P/medios"
swiftc -O scripts/video-prueba.swift -o build/video-prueba
build/video-prueba "$P/medios/01-corto.mp4" || exit 1
cp Recursos/icono.png "$P/medios/02-placa.png"

CABINA_PRUEBA="$P/medios" CABINA_INFORME="$P/informe.txt" \
  build/Cabina.app/Contents/MacOS/Cabina > "$P/salida.log" 2>&1 &
PID=$!

sleep 4;  screencapture -x "$P/captura-1-video.png" 2>/dev/null || echo "sin captura 1"
sleep 9;  screencapture -x "$P/captura-2-imagen.png" 2>/dev/null || echo "sin captura 2"
for _ in $(seq 1 30); do
  grep -q "CONTROL" "$P/informe.txt" 2>/dev/null && break
  sleep 0.5
done
screencapture -x "$P/captura-3-control.png" 2>/dev/null || echo "sin captura 3"
for _ in $(seq 1 30); do
  grep -q "FIN" "$P/informe.txt" 2>/dev/null && break
  sleep 1
done

VIVA=0; kill -0 "$PID" 2>/dev/null && VIVA=1
kill "$PID" 2>/dev/null

echo "----- informe -----"; cat "$P/informe.txt" 2>/dev/null
echo "----- salida de la app -----"; tail -40 "$P/salida.log"
[ "$VIVA" = 1 ] || { echo "La app se cerró sola"; exit 1; }
grep -q "FIN" "$P/informe.txt" || { echo "La autoprueba no terminó"; exit 1; }
if grep -q "^FALLO" "$P/informe.txt"; then echo "Hay comprobaciones fallidas"; exit 1; fi
echo "Autoprueba superada"
