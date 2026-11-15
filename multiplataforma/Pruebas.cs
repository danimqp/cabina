using Avalonia.Threading;

namespace Cabina;

/// Autoprueba para la compilación automática: carga una carpeta, proyecta y deja un informe.
/// Solo se activa con el argumento --autoprueba y las variables CABINA_PRUEBA y CABINA_INFORME.
public static class Pruebas
{
    public static void ArrancarSiProcede(Motor motor, VentanaControl ventana, string[] argumentos)
    {
        var carpeta = Environment.GetEnvironmentVariable("CABINA_PRUEBA");
        var informe = Environment.GetEnvironmentVariable("CABINA_INFORME");
        if (!argumentos.Contains("--autoprueba") || string.IsNullOrEmpty(carpeta) || string.IsNullOrEmpty(informe)) return;
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

            try
            {
                await Task.Delay(1500);
                Anotar(motor.ErrorDeMotor == null, "motor VLC cargado" + (motor.ErrorDeMotor == null ? "" : ": " + motor.ErrorDeMotor));

                var archivos = Directory.GetFiles(carpeta);
                var agregadas = motor.Agregar(archivos);
                Anotar(agregadas >= 2, $"lista: {agregadas} piezas de {archivos.Length} archivos");
                var video = motor.Piezas.FirstOrDefault(p => p.Tipo == TipoPieza.Video);
                var imagen = motor.Piezas.FirstOrDefault(p => p.Tipo == TipoPieza.Imagen);
                if (video == null || imagen == null)
                {
                    Anotar(false, "faltan un vídeo y una imagen en la carpeta de prueba");
                    return;
                }
                await Task.Delay(2500);
                Anotar(video.Duracion is > 1, $"duración detectada del {Path.GetExtension(video.Ruta)}: {video.Duracion} s");

                // Lanzar con la salida cerrada: debe abrirse sola
                motor.Lanzar(video);
                await Task.Delay(3500);
                Anotar(ventana.SalidaAbierta, $"la salida se abre sola al lanzar (en proyector: {ventana.SalidaEnProyector})");
                Anotar(motor.EsVideo && motor.Reproduciendo && motor.Tiempo > 1, $"vídeo MKV en marcha: {motor.Tiempo:0.0} de {motor.Duracion:0.0} s");
                await Capturar("1-video");

                motor.AlternarNegro();
                await Task.Delay(700);
                var congelado = motor.Reproductor?.Time ?? -1;
                await Task.Delay(900);
                var despues = motor.Reproductor?.Time ?? -2;
                Anotar(motor.Negro && !motor.Reproduciendo && congelado == despues, $"negro: vídeo detenido en {congelado} ms");
                await Capturar("2-negro");
                motor.AlternarNegro();
                await Task.Delay(1200);
                Anotar(!motor.Negro && motor.Reproduciendo && (motor.Reproductor?.Time ?? 0) > congelado,
                    $"al quitar negro continúa: {motor.Reproductor?.Time} ms");

                motor.Mover(video, 1);
                Anotar(motor.EsVideo && motor.Reproduciendo && motor.Piezas.IndexOf(video) == 1, "reordenar la lista no interrumpe la proyección");

                motor.Lanzar(imagen);
                await Task.Delay(1200);
                Anotar(motor.EsImagen && motor.ImagenVisible != null && video.Pasada, "imagen en pantalla; el vídeo queda como ya pasado");
                await Capturar("3-imagen");

                motor.Lanzar(video);
                await Task.Delay(1500);
                motor.Buscar(Math.Max(0, motor.Duracion - 3));
                var espera = 0;
                while (motor.EsVideo && espera < 80)
                {
                    await Task.Delay(200);
                    espera++;
                }
                Anotar(motor.Contenido == Contenido.Fondo && !motor.Reproduciendo, "al terminar el vídeo la pantalla vuelve a negro");

                motor.Lanzar(video);
                await Task.Delay(1500);
                ventana.CerrarSalida();
                await Task.Delay(600);
                Anotar(!ventana.SalidaAbierta, "salida cerrada");
                await Capturar("4-control");
                motor.VolverAlFondo();
                Anotar(true, "FIN");
            }
            catch (Exception error)
            {
                Anotar(false, "excepción en la autoprueba: " + error);
            }
        }, DispatcherPriority.Background);
    }
}
