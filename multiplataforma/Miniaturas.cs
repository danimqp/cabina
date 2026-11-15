using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using LibVLCSharp.Shared;

namespace Proyectapp;

/// Datos técnicos de un vídeo, leídos sin reproducirlo.
public sealed record DatosVideo(bool Legible, double Duracion, int Ancho, int Alto, double Fps, bool ConSonido, bool ConImagen)
{
    public string Detalle
    {
        get
        {
            var partes = new List<string>();
            if (Ancho > 0 && Alto > 0) partes.Add($"{Ancho} × {Alto} píxeles");
            if (Fps > 0) partes.Add($"{Fps:0.###} fps");
            partes.Add(ConSonido ? "con sonido" : "sin sonido");
            return string.Join(" · ", partes);
        }
    }
}

/// Saca fotogramas sueltos de un vídeo con un reproductor de VLC aparte, sin ventana ni sonido.
public static class Miniaturas
{
    private static readonly SemaphoreSlim puertaDeDatos = new(1, 1);

    public static async Task<DatosVideo> Datos(LibVLC vlc, string ruta)
    {
        // De uno en uno: varios análisis a la vez sobre el mismo motor no aportan nada y son un riesgo.
        await puertaDeDatos.WaitAsync();
        try
        {
            using var medio = new Media(vlc, ruta, FromType.FromPath);
            var estado = await medio.Parse(MediaParseOptions.ParseLocal, 10000);
            int ancho = 0, alto = 0;
            double fps = 0;
            bool sonido = false, imagen = false;
            foreach (var pista in medio.Tracks)
            {
                if (pista.TrackType == TrackType.Video && !imagen)
                {
                    imagen = true;
                    ancho = (int)pista.Data.Video.Width;
                    alto = (int)pista.Data.Video.Height;
                    if (pista.Data.Video.FrameRateDen > 0) fps = (double)pista.Data.Video.FrameRateNum / pista.Data.Video.FrameRateDen;
                }
                else if (pista.TrackType == TrackType.Audio)
                {
                    sonido = true;
                }
            }
            return new DatosVideo(estado == MediaParsedStatus.Done, Math.Max(0, medio.Duration / 1000.0), ancho, alto, fps, sonido, imagen);
        }
        catch
        {
            return new DatosVideo(false, 0, 0, 0, 0, false, false);
        }
        finally
        {
            puertaDeDatos.Release();
        }
    }

    // Los fotogramas se sacan con un motor VLC aparte, sin ventana ni sonido, y de uno en uno.
    // No se usan funciones de retorno hacia la app: VLC escribe una imagen en disco y la app la lee.
    private static readonly SemaphoreSlim puerta = new(1, 1);
    private static LibVLC? motorDeFotogramas;
    private static readonly string carpeta = Path.Combine(Path.GetTempPath(), "Proyectapp");

    private static LibVLC MotorDeFotogramas() =>
        motorDeFotogramas ??= new LibVLC(
            "--vout=dummy", "--no-audio", "--avcodec-hw=none", "--no-video-title-show", "--no-osd",
            "--no-snapshot-preview", "--no-sub-autodetect-file", "--quiet");

    /// Un fotograma del segundo indicado, reducido para caber en `lado` píxeles.
    public static async Task<Bitmap?> Fotograma(LibVLC vlc, string ruta, double segundo, DatosVideo datos, int lado)
    {
        if (!datos.ConImagen || datos.Ancho <= 0 || datos.Alto <= 0) return null;
        var escala = Math.Min(1.0, (double)lado / Math.Max(datos.Ancho, datos.Alto));
        var ancho = Math.Max(16, (int)(datos.Ancho * escala) / 2 * 2);
        var destino = Path.Combine(carpeta, $"fotograma-{Guid.NewGuid():N}.png");
        await puerta.WaitAsync();
        MediaPlayer? reproductor = null;
        try
        {
            Directory.CreateDirectory(carpeta);
            var motor = MotorDeFotogramas();
            var conImagen = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            reproductor = new MediaPlayer(motor) { EnableKeyInput = false, EnableMouseInput = false };
            reproductor.Vout += (_, e) =>
            {
                if (e.Count > 0) conImagen.TrySetResult(true);
            };
            reproductor.EncounteredError += (_, _) => conImagen.TrySetResult(false);
            reproductor.EndReached += (_, _) => conImagen.TrySetResult(false);
            using (var medio = new Media(motor, ruta, FromType.FromPath))
            {
                medio.AddOption(":no-audio");
                medio.AddOption(":no-spu");
                medio.AddOption(FormattableString.Invariant($":start-time={Math.Max(0, segundo):0.###}"));
                reproductor.Play(medio);
            }
            var ganadora = await Task.WhenAny(conImagen.Task, Task.Delay(7000));
            byte[]? bytes = null;
            if (ganadora == conImagen.Task && conImagen.Task.Result)
            {
                for (var intento = 0; intento < 8 && bytes == null; intento++)
                {
                    await Task.Delay(150);
                    if (!reproductor.TakeSnapshot(0, destino, (uint)ancho, 0)) continue;
                    for (var espera = 0; espera < 10 && bytes == null; espera++)
                    {
                        await Task.Delay(60);
                        try
                        {
                            if (File.Exists(destino) && new FileInfo(destino).Length > 0) bytes = await File.ReadAllBytesAsync(destino);
                        }
                        catch
                        {
                            bytes = null;
                        }
                    }
                }
            }
            return bytes == null ? null : new Bitmap(new MemoryStream(bytes));
        }
        catch
        {
            return null;
        }
        finally
        {
            var aCerrar = reproductor;
            if (aCerrar != null)
            {
                try { await Task.Run(() => aCerrar.Stop()); } catch { /* ya detenido */ }
                try { aCerrar.Dispose(); } catch { /* ya cerrado */ }
            }
            try { File.Delete(destino); } catch { /* temporal */ }
            puerta.Release();
        }
    }

    /// Abre una imagen ya reducida a `lado` píxeles de ancho. Se decodifica directamente a ese tamaño:
    /// la copia no depende de la imagen original ni de su memoria.
    public static Bitmap? ImagenReducida(string ruta, int lado)
    {
        try
        {
            if (!Formatos.EsArchivoNormal(ruta)) return null;
            using var flujo = File.OpenRead(ruta);
            var completa = new Bitmap(flujo);
            if (completa.PixelSize.Width <= lado) return completa;
            // Más ancha de lo necesario: se vuelve a leer del archivo ya reducida, sin ampliar nunca las pequeñas.
            flujo.Position = 0;
            var reducida = Bitmap.DecodeToWidth(flujo, lado, BitmapInterpolationMode.MediumQuality);
            completa.Dispose();
            return reducida;
        }
        catch
        {
            return null;
        }
    }
}
