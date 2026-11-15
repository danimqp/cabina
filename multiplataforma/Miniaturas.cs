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
    public static async Task<DatosVideo> Datos(LibVLC vlc, string ruta)
    {
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
    }

    /// Un fotograma del segundo indicado, reducido para caber en `lado` píxeles.
    public static async Task<Bitmap?> Fotograma(LibVLC vlc, string ruta, double segundo, DatosVideo datos, int lado)
    {
        if (!datos.ConImagen || datos.Ancho <= 0 || datos.Alto <= 0) return null;
        var escala = Math.Min(1.0, (double)lado / Math.Max(datos.Ancho, datos.Alto));
        var ancho = Math.Max(16, (int)(datos.Ancho * escala) / 2 * 2);
        var alto = Math.Max(16, (int)(datos.Alto * escala) / 2 * 2);
        var paso = ancho * 4;
        var memoria = Marshal.AllocHGlobal(paso * alto);
        MediaPlayer? reproductor = null;
        try
        {
            var listo = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            var mostrados = 0;
            MediaPlayer.LibVLCVideoLockCb bloquear = (opaco, planos) =>
            {
                Marshal.WriteIntPtr(planos, memoria);
                return IntPtr.Zero;
            };
            MediaPlayer.LibVLCVideoDisplayCb mostrar = (opaco, imagen) =>
            {
                if (Interlocked.Increment(ref mostrados) >= 2) listo.TrySetResult(true);
            };
            reproductor = new MediaPlayer(vlc) { Mute = true };
            reproductor.SetVideoFormat("RV32", (uint)ancho, (uint)alto, (uint)paso);
            reproductor.SetVideoCallbacks(bloquear, null, mostrar);
            reproductor.EncounteredError += (_, _) => listo.TrySetResult(false);
            reproductor.EndReached += (_, _) => listo.TrySetResult(false);
            using (var medio = new Media(vlc, ruta, FromType.FromPath))
            {
                medio.AddOption(":no-audio");
                medio.AddOption(":no-spu");
                medio.AddOption(":no-sub-autodetect-file");
                medio.AddOption(FormattableString.Invariant($":start-time={Math.Max(0, segundo):0.###}"));
                reproductor.Play(medio);
            }
            var ganadora = await Task.WhenAny(listo.Task, Task.Delay(6000));
            var conseguido = ganadora == listo.Task && listo.Task.Result;
            var aDetener = reproductor;
            await Task.Run(() => aDetener.Stop());
            GC.KeepAlive(bloquear);
            GC.KeepAlive(mostrar);
            if (!conseguido) return null;

            var mapa = new WriteableBitmap(new PixelSize(ancho, alto), new Vector(96, 96), PixelFormat.Bgra8888, AlphaFormat.Opaque);
            using (var cerrojo = mapa.Lock())
            {
                unsafe
                {
                    for (var fila = 0; fila < alto; fila++)
                    {
                        Buffer.MemoryCopy(
                            (void*)(memoria + fila * paso), (void*)(cerrojo.Address + fila * cerrojo.RowBytes),
                            cerrojo.RowBytes, Math.Min(paso, cerrojo.RowBytes));
                    }
                }
            }
            return mapa;
        }
        catch
        {
            return null;
        }
        finally
        {
            try { reproductor?.Dispose(); } catch { /* ya detenido */ }
            Marshal.FreeHGlobal(memoria);
        }
    }

    /// Abre una imagen reducida a `lado` píxeles de ancho como mucho.
    public static Bitmap? ImagenReducida(string ruta, int lado)
    {
        try
        {
            if (!Formatos.EsArchivoNormal(ruta)) return null;
            using var flujo = File.OpenRead(ruta);
            var completa = new Bitmap(flujo);
            if (completa.PixelSize.Width <= lado && completa.PixelSize.Height <= lado) return completa;
            var escala = (double)lado / Math.Max(completa.PixelSize.Width, completa.PixelSize.Height);
            var reducida = completa.CreateScaledBitmap(
                new PixelSize(Math.Max(1, (int)(completa.PixelSize.Width * escala)), Math.Max(1, (int)(completa.PixelSize.Height * escala))),
                BitmapInterpolationMode.HighQuality);
            completa.Dispose();
            return reducida;
        }
        catch
        {
            return null;
        }
    }
}
