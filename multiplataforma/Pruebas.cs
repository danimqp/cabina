using Avalonia.Threading;

namespace Proyectapp;

/// Autoprueba para la compilación automática: carga una carpeta, proyecta y deja un informe.
/// Solo se activa con el argumento --autoprueba y las variables PROYECTAPP_PRUEBA y PROYECTAPP_INFORME.
/// Las líneas «CAPTURA nombre» piden al script una captura de pantalla en ese momento.
public static class Pruebas
{
    public static bool Activa(string[] argumentos) =>
        argumentos.Contains("--autoprueba")
        && !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("PROYECTAPP_PRUEBA"))
        && !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("PROYECTAPP_INFORME"));

    public static void ArrancarSiProcede(Motor motor, VentanaControl ventana, string[] argumentos)
    {
        if (!Activa(argumentos)) return;
        var carpeta = Environment.GetEnvironmentVariable("PROYECTAPP_PRUEBA")!;
        var informe = Environment.GetEnvironmentVariable("PROYECTAPP_INFORME")!;
        Dispatcher.UIThread.Post(async () =>
        {
            var lineas = new List<string>();
            void Escribir(string linea)
            {
                lineas.Add(linea);
                try { File.WriteAllLines(informe, lineas); } catch { /* se reintenta en la siguiente línea */ }
            }
            void Anotar(bool correcto, string texto) => Escribir((correcto ? "OK    " : "FALLO ") + texto);
            async Task Capturar(string nombre)
            {
                Escribir("CAPTURA " + nombre);
                await Task.Delay(2200);
            }
            async Task<bool> Hasta(Func<bool> condicion, double segundos)
            {
                for (var i = 0; i < segundos * 5 && !condicion(); i++) await Task.Delay(200);
                return condicion();
            }
            long Ms() => motor.Reproductor?.Time ?? -1;

            try
            {
                await Task.Delay(1500);
                Anotar(motor.ErrorDeMotor == null, "motor VLC cargado" + (motor.ErrorDeMotor == null ? "" : ": " + motor.ErrorDeMotor));
                Anotar(true, $"salidas de sonido: {motor.Dispositivos.Count} · atajos globales: {Plataforma.AtajosRegistrados}");

                var todos = Directory.GetFiles(carpeta);
                var audios = todos.Where(a => Formatos.Audio.Contains(Formatos.Extension(a))).ToList();
                var medios = todos.Where(a => Formatos.TipoDeArchivo(a) != null).ToList();
                var agregadas = motor.Agregar(medios);
                Anotar(agregadas >= 2, $"lista: {agregadas} piezas de {medios.Count} archivos");
                var video = motor.Piezas.FirstOrDefault(p => p.Tipo == TipoPieza.Video);
                var imagen = motor.Piezas.FirstOrDefault(p => p.Tipo == TipoPieza.Imagen);
                if (video == null || imagen == null)
                {
                    Anotar(false, "faltan un vídeo y una imagen en la carpeta de prueba");
                    return;
                }
                Anotar(await Hasta(() => video.Duracion is > 1, 8), $"duración detectada del {Formatos.Extension(video.Ruta)}: {video.Duracion} s");
                Anotar(video.Subtitulos != null, "subtítulos .srt asociados solos: " + Path.GetFileName(video.Subtitulos ?? "ninguno"));
                Anotar(await Hasta(() => motor.MiniaturasDeLista.Count >= 2, 15), $"miniaturas de la lista: {motor.MiniaturasDeLista.Count}");
                var previaVideo = await motor.PreviaDe(video);
                Anotar(previaVideo.Fotogramas.Count >= 3 && previaVideo.Detalle.Contains("640"),
                    $"previsualización: {previaVideo.Fotogramas.Count} fotogramas · {previaVideo.Detalle}");

                motor.Comprobar(avisar: true);
                await Hasta(() => !motor.Comprobando, 10);
                Anotar(!motor.Comprobando && !motor.Problemas.Values.Any(p => p.Grave) && motor.Faltantes.Count == 0,
                    "comprobación: " + (motor.Nota ?? motor.Aviso ?? "sin resultado"));

                // Vídeo: la salida se abre sola
                motor.Lanzar(video);
                Anotar(await Hasta(() => motor.EsVideo && motor.Tiempo > 1.5, 10) && motor.Reproduciendo,
                    $"vídeo en marcha: {motor.Tiempo:0.0} de {motor.Duracion:0.0} s");
                Anotar(ventana.SalidaAbierta, $"la salida se abre sola al lanzar (en proyector: {ventana.SalidaEnProyector})");
                Escribir((await Hasta(() => motor.Previa != null, 5) ? "OK    " : "AVISO ") + "miniatura en vivo de lo que ve el público");
                await Capturar("1-video");

                // Negro
                motor.AlternarNegro();
                await Task.Delay(900);
                var congelado = Ms();
                await Task.Delay(900);
                Anotar(motor.Negro && !motor.Reproduciendo && Ms() == congelado, $"negro: vídeo detenido en {congelado} ms");
                motor.AlternarNegro();
                await Task.Delay(1200);
                Anotar(!motor.Negro && motor.Reproduciendo && Ms() > congelado, $"al quitar negro continúa: {Ms()} ms");

                // Lista y volumen propio
                motor.Mover(video, 1);
                Anotar(motor.EsVideo && motor.Reproduciendo && motor.Piezas.IndexOf(video) == 1, "reordenar la lista no interrumpe la proyección");
                motor.FijarVolumen(0.5);
                Anotar(video.Volumen == 0.5 && motor.Funcion.Volumen == 1, "el volumen cambiado durante el vídeo se guarda en ese vídeo");

                // Mensaje que corta el vídeo: el punto queda guardado
                await Hasta(() => motor.Tiempo > 6.5, 10);
                var corte = motor.Tiempo;
                motor.MostrarMensaje("Empezamos en 10 minutos");
                Anotar(motor.EsImagen && motor.EsMensaje && motor.ImagenVisible != null, "mensaje rápido en pantalla");
                Anotar(video.Posicion is { } guardado && Math.Abs(guardado - corte) < 2, $"punto del corte guardado: {video.Posicion:0.0} (cortado en {corte:0.0})");
                await Capturar("2-mensaje");

                // Cuenta atrás
                motor.IniciarCuenta(90, "");
                var primera = motor.ImagenVisible;
                await Task.Delay(1700);
                Anotar(motor.EsMensaje && motor.TituloEnPantalla.StartsWith("Cuenta atrás") && !ReferenceEquals(primera, motor.ImagenVisible),
                    "cuenta atrás en pantalla y avanzando");

                // Música de espera
                if (audios.Count > 0)
                {
                    motor.FijarMusica(audios);
                    motor.EncenderMusica();
                    Anotar(await Hasta(() => motor.MusicaSonando, 6) && motor.MusicaEncendida, $"música de espera sonando: «{motor.PistaMusica}»");
                }
                else
                {
                    Anotar(false, "falta el audio de prueba");
                }

                // Seguir donde se cortó: la música se calla
                var punto = video.Posicion ?? 0;
                motor.Lanzar(video, video.Posicion);
                Anotar(await Hasta(() => motor.EsVideo && motor.Tiempo >= punto + 0.5, 10) && motor.Tiempo < punto + 6,
                    $"el vídeo sigue desde el corte: {motor.Tiempo:0.0} (guardado {punto:0.0})");
                Anotar(await Hasta(() => !motor.MusicaSonando, 5) && motor.MusicaEncendida, "la música se calla durante el vídeo");

                // Final natural: fondo, punto olvidado y música de vuelta
                Anotar(await Hasta(() => !motor.EsVideo, 20) && motor.Contenido == Contenido.Fondo, "al terminar el vídeo vuelve al fondo");
                Anotar(video.Posicion == null && video.Pasada, "al terminar entero se olvida el punto y queda como ya pasado");
                Anotar(await Hasta(() => motor.MusicaSonando, 6), "la música vuelve sola al terminar el vídeo");
                motor.ApagarMusica();
                Anotar(await Hasta(() => !motor.MusicaSonando, 6) && !motor.MusicaEncendida, "la música se apaga al pararla");

                // Imagen fija y mini control
                motor.Lanzar(imagen);
                Anotar(await Hasta(() => motor.EsImagen && !motor.EsMensaje && motor.ImagenVisible != null, 5), "imagen en pantalla");
                ventana.MostrarMini();
                await Task.Delay(400);
                Anotar(ventana.MiniVisible, "mini control flotante visible");
                await Capturar("3-imagen");
                ventana.OcultarMini();
                motor.VolverAlFondo();
                Anotar(motor.Contenido == Contenido.Fondo, "volver al fondo retira la imagen");

                // Mensaje guardado, recorte y encadenado
                motor.AgregarMensaje("Conversatorio con el equipo");
                var mensaje = motor.Piezas.LastOrDefault();
                Anotar(mensaje?.Tipo == TipoPieza.Texto, "mensaje añadido a la lista");
                if (mensaje != null)
                {
                    motor.Mover(video, -1);
                    motor.Mover(mensaje, -1);
                    Anotar(motor.Piezas.IndexOf(mensaje) == motor.Piezas.IndexOf(video) + 1, "el mensaje queda justo detrás del vídeo");
                    motor.Lanzar(video);
                    await Hasta(() => motor.EsVideo && motor.Tiempo > 1.2, 10);
                    motor.MarcarInicio();
                    await Hasta(() => motor.Tiempo > (video.Inicio ?? 0) + 1.6, 10);
                    motor.MarcarFin();
                    Anotar(video.Inicio > 0.8 && video.Fin > video.Inicio + 1, $"recorte marcado: de {video.Inicio:0.0} a {video.Fin:0.0}");
                    motor.VolverAlFondo();
                    motor.OlvidarPosicion(video);
                    motor.AlternarEncadenado(video);
                    motor.Lanzar(video);
                    Anotar(await Hasta(() => motor.EnPantalla == mensaje && motor.EsMensaje, 12),
                        "al llegar a la marca de fin lanza sola la pieza siguiente");
                    motor.QuitarRecorte(video);
                    motor.AlternarEncadenado(video);
                    motor.VolverAlFondo();
                }

                // Guardar, abrir y reunir archivos
                var temporal = Path.Combine(Path.GetDirectoryName(informe)!, "funcion.proyectapp");
                var cuantas = motor.Piezas.Count;
                Anotar(motor.GuardarComo(temporal) && File.Exists(temporal), "función guardada en un archivo");
                motor.Nueva();
                Anotar(motor.Piezas.Count == 0, "función nueva: lista vacía");
                Anotar(motor.Abrir(temporal) && motor.Piezas.Count == cuantas, $"función abierta de nuevo: {motor.Piezas.Count} piezas");
                video = motor.Piezas.First(p => p.Tipo == TipoPieza.Video);
                var reunidos = Path.Combine(Path.GetDirectoryName(informe)!, "reunidos");
                Directory.CreateDirectory(reunidos);
                await motor.Reunir(reunidos);
                var dentro = motor.Piezas.Where(p => p.Tipo != TipoPieza.Texto).All(p => p.Ruta.StartsWith(reunidos) && File.Exists(p.Ruta));
                Anotar(dentro && Directory.GetFiles(reunidos, "*.proyectapp").Length == 1, "archivos reunidos en una carpeta: " + (motor.Nota ?? motor.Aviso));

                // Ventana de control a la vista
                await Hasta(() => motor.MiniaturasDeLista.Count >= 2, 10);
                motor.Lanzar(video);
                await Hasta(() => motor.EsVideo && motor.Tiempo > 1.5, 10);
                ventana.CerrarSalida();
                await Task.Delay(600);
                Anotar(!ventana.SalidaAbierta && !motor.EsVideo, "cerrar la salida con un vídeo en marcha lo detiene sin problemas");
                await Capturar("4-control");
                Anotar(true, "FIN");
            }
            catch (Exception error)
            {
                Anotar(false, "excepción en la autoprueba: " + error);
            }
        }, DispatcherPriority.Background);
    }
}
