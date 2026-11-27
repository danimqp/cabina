# Proyectapp

App para proyectar cortometrajes e imágenes, uno tras otro, en muestras, cineclubes y cine comunitario.
Una sola app para **Windows y Mac**, con el motor de vídeo de VLC dentro (no hace falta instalar VLC).

App desarrollada por [Muyuna.org](https://muyuna.org).

## Descargar

https://github.com/danimqp/cabina/releases/tag/proyectapp

- **Windows:** `Proyectapp-Instalador.exe` (o `Proyectapp-Windows.zip`, que funciona sin instalar).
- **Mac con Apple Silicon:** `Proyectapp-Mac.dmg`. **Mac con Intel:** `Proyectapp-Mac-Intel.dmg`.

La primera vez, Windows («Más información» > «Ejecutar de todas formas») y macOS
(Ajustes del Sistema > Privacidad y seguridad > «Abrir igualmente») avisan de que la app no está firmada.

## Qué hace

- Lista de vídeos, imágenes y mensajes de texto; se ordena arrastrando con el ratón y se edita también mientras se proyecta.
- Cada pieza se lanza a mano; al terminar un vídeo la pantalla vuelve sola al fondo.
- NEGRO, pausa, barra de tiempo, volumen general y por vídeo, seguir donde se cortó.
- Mensajes rápidos y cuenta atrás; música de espera; imagen y color de fondo; salida de sonido propia.
- Subtítulos, recorte de inicio y fin, encadenar piezas, comprobar archivos, reunirlos en una carpeta.
- Miniaturas que se recorren con el ratón y tira de fotogramas del vídeo seleccionado (pulsa uno para lanzar desde ahí); miniatura de lo que ve el público; mini control flotante.
- Ajustar proyección: imagen de prueba, elegir la pantalla de salida, encuadre (imagen completa, llenar la pantalla o quitar las bandas negras que trae el vídeo), tamaño, posición y márgenes. Se guarda con la función.
- Formatos de VLC: MP4, MOV, MKV, AVI, WMV, MPG, WebM…

Hecho con .NET 8, Avalonia y LibVLCSharp. LibVLC se distribuye bajo licencia LGPL 2.1 (videolan.org).
