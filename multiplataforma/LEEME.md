# Cabina · prototipo multiplataforma (motor VLC)

Versión de prueba de Cabina para **Windows y Mac** con el motor de vídeo de VLC dentro de la app
(no hace falta instalar VLC). Sirve para validar lo esencial antes de portar el resto de funciones:

- lista de vídeos e imágenes, con arrastrar archivos y reordenar;
- lanzar cada pieza a la salida (proyector como pantalla ampliada, o ventana de prueba);
- pausa, barra de tiempo, volumen y NEGRO;
- formatos de VLC: MP4, MOV, MKV, AVI, WMV, MPG, WebM…

Todavía **no** tiene: mensajes y cuenta atrás, música de espera, subtítulos externos, recorte,
guardado de la función ni vista previa. La versión completa sigue siendo la de Mac (carpeta raíz).

Descargas: https://github.com/danimqp/cabina/releases/tag/prototipo

Hecho con .NET 8, Avalonia y LibVLCSharp. LibVLC se distribuye bajo licencia LGPL 2.1 (videolan.org).
