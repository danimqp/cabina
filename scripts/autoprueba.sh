#!/bin/bash
# Arranca la app recién compilada con medios de prueba y comprueba su informe.
# La app pide capturas escribiendo líneas «CAPTURA nombre» en el informe.
set -uo pipefail
cd "$(dirname "$0")/.."

P="$PWD/build/prueba"
rm -rf "$P"; mkdir -p "$P/medios"
swiftc -O scripts/video-prueba.swift -o build/video-prueba
build/video-prueba "$P/medios/01-corto.mp4" || exit 1
cp Recursos/icono.png "$P/medios/02-placa.png"
python3 - "$P/medios/musica-de-espera.wav" <<'PY'
import math, struct, sys, wave
with wave.open(sys.argv[1], "w") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050)
    w.writeframes(b"".join(struct.pack("<h", int(2500 * math.sin(2 * math.pi * 330 * i / 22050))) for i in range(22050 * 40)))
PY

CABINA_PRUEBA="$P/medios" CABINA_INFORME="$P/informe.txt" \
  build/Cabina.app/Contents/MacOS/Cabina > "$P/salida.log" 2>&1 &
PID=$!

HECHAS=""
for _ in $(seq 1 300); do
  if [ -f "$P/informe.txt" ]; then
    for NOMBRE in $(grep "^CAPTURA " "$P/informe.txt" | cut -d' ' -f2); do
      case " $HECHAS " in *" $NOMBRE "*) ;; *)
        sleep 0.5
        screencapture -x "$P/captura-$NOMBRE.png" 2>/dev/null || echo "sin captura $NOMBRE"
        HECHAS="$HECHAS $NOMBRE";;
      esac
    done
    grep -q "FIN" "$P/informe.txt" && break
  fi
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.3
done

VIVA=0; kill -0 "$PID" 2>/dev/null && VIVA=1
kill "$PID" 2>/dev/null

echo "----- informe -----"; cat "$P/informe.txt" 2>/dev/null
echo "----- salida de la app -----"; tail -40 "$P/salida.log"
[ "$VIVA" = 1 ] || { echo "La app se cerró sola"; exit 1; }
grep -q "FIN" "$P/informe.txt" || { echo "La autoprueba no terminó"; exit 1; }
if grep -q "^FALLO" "$P/informe.txt"; then echo "Hay comprobaciones fallidas"; exit 1; fi
echo "Autoprueba superada"
