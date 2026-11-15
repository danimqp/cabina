#!/bin/bash
# Arranca la app de Mac con los medios de prueba y comprueba su informe.
set -uo pipefail
cd "$(dirname "$0")/.."
P="$PWD/salida/prueba"; rm -rf "$P"; mkdir -p "$P"
CABINA_PRUEBA="$PWD/pruebas/medios" CABINA_INFORME="$P/informe.txt" \
  "salida/Cabina VLC.app/Contents/MacOS/Cabina" --autoprueba > "$P/salida.log" 2>&1 &
PID=$!
HECHAS=""
for _ in $(seq 1 400); do
  if [ -f "$P/informe.txt" ]; then
    for NOMBRE in $(grep "^CAPTURA " "$P/informe.txt" | cut -d' ' -f2); do
      case " $HECHAS " in *" $NOMBRE "*) ;; *)
        sleep 0.7; screencapture -x "$P/captura-$NOMBRE.png" 2>/dev/null || echo "sin captura $NOMBRE"
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
echo "----- salida de la app -----"; tail -30 "$P/salida.log"
[ "$VIVA" = 1 ] || { echo "La app se cerró sola"; exit 1; }
grep -q "FIN" "$P/informe.txt" || { echo "La autoprueba no terminó"; exit 1; }
if grep -q "^FALLO" "$P/informe.txt"; then echo "Hay comprobaciones fallidas"; exit 1; fi
echo "Autoprueba superada"
