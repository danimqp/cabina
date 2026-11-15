using Avalonia.Media.Imaging;
using Avalonia.Threading;
using LibVLCSharp.Shared;

namespace Cabina;

public enum TipoPieza { Video, Imagen }

public enum Contenido { Fondo, Video, Imagen }

/// Un elemento de la lista: un vídeo o una imagen.
public sealed class Pieza
{
    public Guid Id { get; } = Guid.NewGuid();
    public string Nombre { get; set; } = "";
    public string Ruta { get; set; } = "";
    public TipoPieza Tipo { get; set; }
    public double? Duracion { get; set; }
    public bool Pasada { get; set; }
}

/// Estado y lógica de la función. Todo su estado se lee y se cambia desde el hilo de la interfaz;
/// las órdenes al motor VLC van por una cola propia para que nunca bloqueen los controles.
public sealed class Motor : IDisposable
{
    public static readonly string[] ExtensionesVideo =
    {
        "mp4", "mov", "m4v", "mkv", "avi", "wmv", "mpg", "mpeg", "webm", "flv", "ts", "m2ts", "mts", "3gp", "ogv", "vob", "divx",
    };

    public static readonly string[] ExtensionesImagen = { "jpg", "jpeg", "png", "bmp", "webp" };

    public List<Pieza> Piezas { get; } = new();
    public Contenido Contenido { get; private set; } = Contenido.Fondo;
    public Pieza? EnPantalla { get; private set; }
    public Pieza? UltimaLanzada { get; private set; }
    public Bitmap? ImagenVisible { get; private set; }
    public bool Negro { get; private set; }
    public bool Reproduciendo { get; private set; }
    public double Tiempo { get; private set; }
    public double Duracion { get; private set; }
    public double Volumen { get; private set; } = 1;
    public string? Aviso { get; set; }
    public string? ErrorDeMotor { get; }
    public Guid? Seleccion { get; set; }

    /// El reproductor de VLC; es nulo si el motor no se pudo cargar.
    public MediaPlayer? Reproductor { get; }

    /// Cambió el estado (tiempo, negro, contenido…).
    public event Action? Cambio;

    /// Cambió la lista (piezas, orden, duraciones, marcas).
    public event Action? CambioDeLista;

    /// La ventana de control la define: abre la salida si hace falta y dice si ya estaba lista.
    public Func<bool>? AsegurarSalida { get; set; }

    private readonly LibVLC? vlc;
    private readonly DispatcherTimer reloj;
    private readonly object candado = new();
    private Task cola = Task.CompletedTask;
    private bool reanudarTrasNegro;
    private DateTime ultimoLanzamiento = DateTime.MinValue;
    private bool cerrado;

    public Motor()
    {
        try
        {
            Core.Initialize();
            vlc = new LibVLC("--no-video-title-show", "--no-osd", "--no-snapshot-preview", "--quiet");
            Reproductor = new MediaPlayer(vlc)
            {
                EnableKeyInput = false,
                EnableMouseInput = false,
            };
            Reproductor.EndReached += (_, _) => Dispatcher.UIThread.Post(AlTerminarVideo);
            Reproductor.EncounteredError += (_, _) => Dispatcher.UIThread.Post(AlFallarVideo);
        }
        catch (Exception error)
        {
            ErrorDeMotor = "No se pudo cargar el motor de vídeo VLC: " + error.Message;
            Aviso = ErrorDeMotor;
        }

        reloj = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        reloj.Tick += (_, _) => Tic();
        reloj.Start();
    }

    // ----- Consultas -----

    public bool EsVideo => Contenido == Contenido.Video;
    public bool EsImagen => Contenido == Contenido.Imagen;
    public double Restante => Math.Max(0, Duracion - Tiempo);

    public Pieza? Siguiente
    {
        get
        {
            if (Piezas.Count == 0) return null;
            var i = UltimaLanzada == null ? -1 : Piezas.IndexOf(UltimaLanzada);
            if (UltimaLanzada != null && i < 0) return Piezas[0];
            return i + 1 < Piezas.Count ? Piezas[i + 1] : null;
        }
    }

    public double DuracionTotal => Piezas.Sum(p => p.Duracion ?? 0);

    public static TipoPieza? TipoDeArchivo(string ruta)
    {
        var ext = Path.GetExtension(ruta).TrimStart('.').ToLowerInvariant();
        if (ExtensionesVideo.Contains(ext)) return TipoPieza.Video;
        if (ExtensionesImagen.Contains(ext)) return TipoPieza.Imagen;
        return null;
    }

    public static string TextoDeTiempo(double segundos)
    {
        if (double.IsNaN(segundos) || double.IsInfinity(segundos) || segundos <= 0 || segundos > 1e9) return "00:00";
        var total = (long)Math.Floor(segundos);
        var h = total / 3600;
        var m = total % 3600 / 60;
        var s = total % 60;
        return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m:00}:{s:00}";
    }

    // ----- Lista -----

    public int Agregar(IEnumerable<string> rutas)
    {
        var entrada = rutas.ToList();
        var nuevas = new List<Pieza>();
        foreach (var ruta in entrada.OrderBy(r => Path.GetFileName(r), StringComparer.CurrentCultureIgnoreCase))
        {
            var tipo = TipoDeArchivo(ruta);
            if (tipo == null) continue;
            nuevas.Add(new Pieza { Nombre = Path.GetFileNameWithoutExtension(ruta), Ruta = ruta, Tipo = tipo.Value });
        }
        Piezas.AddRange(nuevas);
        var descartados = entrada.Count - nuevas.Count;
        if (descartados > 0) Aviso = $"{descartados} archivo(s) no se añadieron: no son vídeos ni imágenes que Cabina reconozca.";
        foreach (var pieza in nuevas.Where(p => p.Tipo == TipoPieza.Video)) _ = CargarDuracion(pieza);
        CambioDeLista?.Invoke();
        Cambio?.Invoke();
        return nuevas.Count;
    }

    private async Task CargarDuracion(Pieza pieza)
    {
        if (vlc == null) return;
        try
        {
            using var medio = new Media(vlc, pieza.Ruta, FromType.FromPath);
            await medio.Parse(MediaParseOptions.ParseLocal, 8000);
            var ms = medio.Duration;
            if (ms > 0)
            {
                Dispatcher.UIThread.Post(() =>
                {
                    pieza.Duracion = ms / 1000.0;
                    CambioDeLista?.Invoke();
                });
            }
        }
        catch
        {
            // Sin duración conocida: la pieza se puede lanzar igualmente.
        }
    }

    public void Quitar(Pieza pieza)
    {
        var i = Piezas.IndexOf(pieza);
        if (i < 0) return;
        if (UltimaLanzada == pieza) UltimaLanzada = i > 0 ? Piezas[i - 1] : null;
        Piezas.RemoveAt(i);
        if (Seleccion == pieza.Id) Seleccion = null;
        CambioDeLista?.Invoke();
        Cambio?.Invoke();
    }

    public void Mover(Pieza pieza, int salto)
    {
        var i = Piezas.IndexOf(pieza);
        var j = i + salto;
        if (i < 0 || j < 0 || j >= Piezas.Count) return;
        Piezas.RemoveAt(i);
        Piezas.Insert(j, pieza);
        CambioDeLista?.Invoke();
        Cambio?.Invoke();
    }

    // ----- Lanzar -----

    public void Lanzar(Pieza pieza)
    {
        if (!Piezas.Contains(pieza)) return;
        if (!File.Exists(pieza.Ruta))
        {
            Aviso = $"No se encuentra el archivo de «{pieza.Nombre}». El proyector no ha cambiado.";
            Cambio?.Invoke();
            return;
        }

        if (pieza.Tipo == TipoPieza.Video)
        {
            if (Reproductor == null || vlc == null)
            {
                Aviso = ErrorDeMotor ?? "El motor de vídeo no está disponible.";
                Cambio?.Invoke();
                return;
            }
            // VLC necesita que la ventana de salida exista antes de reproducir; si no, abriría una ventana propia.
            if (AsegurarSalida != null && !AsegurarSalida())
            {
                Dispatcher.UIThread.Post(() => Lanzar(pieza), DispatcherPriority.Background);
                return;
            }
            MarcarPasadaLaActual();
            var ruta = pieza.Ruta;
            var volumen = (int)Math.Round(Volumen * 100);
            var reproductor = Reproductor;
            var motorVlc = vlc;
            Encolar(() =>
            {
                using var medio = new Media(motorVlc, ruta, FromType.FromPath);
                reproductor.Play(medio);
                reproductor.Volume = volumen;
            });
            ImagenVisible = null;
            Contenido = Contenido.Video;
            Tiempo = 0;
            Duracion = pieza.Duracion ?? 0;
            Reproduciendo = true;
            ultimoLanzamiento = DateTime.UtcNow;
        }
        else
        {
            Bitmap imagen;
            try
            {
                imagen = new Bitmap(pieza.Ruta);
            }
            catch
            {
                Aviso = $"No se pudo abrir la imagen «{pieza.Nombre}». El proyector no ha cambiado.";
                Cambio?.Invoke();
                return;
            }
            MarcarPasadaLaActual();
            DetenerVideo();
            ImagenVisible = imagen;
            Contenido = Contenido.Imagen;
            Tiempo = 0;
            Duracion = 0;
            Reproduciendo = false;
        }

        EnPantalla = pieza;
        UltimaLanzada = pieza;
        pieza.Pasada = false;
        reanudarTrasNegro = false;
        Negro = false;
        Aviso = null;
        CambioDeLista?.Invoke();
        Cambio?.Invoke();
    }

    public void LanzarSiguiente()
    {
        var siguiente = Siguiente;
        if (siguiente != null) Lanzar(siguiente);
    }

    /// Retira la pieza y deja la pantalla en negro.
    public void VolverAlFondo()
    {
        MarcarPasadaLaActual();
        DetenerVideo();
        ImagenVisible = null;
        Contenido = Contenido.Fondo;
        EnPantalla = null;
        Reproduciendo = false;
        reanudarTrasNegro = false;
        Tiempo = 0;
        Duracion = 0;
        CambioDeLista?.Invoke();
        Cambio?.Invoke();
    }

    private void MarcarPasadaLaActual()
    {
        if (EnPantalla != null) EnPantalla.Pasada = true;
    }

    private void DetenerVideo()
    {
        var reproductor = Reproductor;
        if (reproductor == null) return;
        Encolar(() => reproductor.Stop());
    }

    // ----- Transporte -----

    public void AlternarPausa()
    {
        if (!EsVideo || Reproductor == null) return;
        var reproductor = Reproductor;
        if (Reproduciendo)
        {
            Encolar(() => reproductor.SetPause(true));
            Reproduciendo = false;
        }
        else
        {
            reanudarTrasNegro = false;
            Negro = false;
            Encolar(() => reproductor.SetPause(false));
            Reproduciendo = true;
        }
        Cambio?.Invoke();
    }

    public void AlternarNegro()
    {
        var reproductor = Reproductor;
        if (Negro)
        {
            Negro = false;
            if (reanudarTrasNegro && EsVideo && reproductor != null)
            {
                Encolar(() => reproductor.SetPause(false));
                Reproduciendo = true;
            }
            reanudarTrasNegro = false;
        }
        else
        {
            reanudarTrasNegro = EsVideo && Reproduciendo;
            if (reanudarTrasNegro && reproductor != null) Encolar(() => reproductor.SetPause(true));
            Reproduciendo = false;
            Negro = true;
        }
        Cambio?.Invoke();
    }

    public void Buscar(double segundos)
    {
        if (!EsVideo || Reproductor == null || Duracion <= 0) return;
        var destino = Math.Clamp(segundos, 0, Math.Max(0, Duracion - 0.3));
        var reproductor = Reproductor;
        Encolar(() => reproductor.Time = (long)(destino * 1000));
        Tiempo = destino;
        Cambio?.Invoke();
    }

    public void FijarVolumen(double valor)
    {
        Volumen = Math.Clamp(valor, 0, 1);
        var reproductor = Reproductor;
        var entero = (int)Math.Round(Volumen * 100);
        if (reproductor != null) Encolar(() => reproductor.Volume = entero);
        Cambio?.Invoke();
    }

    private void Tic()
    {
        if (!EsVideo || Reproductor == null) return;
        var ms = Reproductor.Time;
        var largo = Reproductor.Length;
        var cambia = false;
        if (ms >= 0 && Math.Abs(ms / 1000.0 - Tiempo) > 0.05 && !Negro && Reproduciendo)
        {
            Tiempo = ms / 1000.0;
            cambia = true;
        }
        if (largo > 0 && Math.Abs(largo / 1000.0 - Duracion) > 0.05)
        {
            Duracion = largo / 1000.0;
            cambia = true;
        }
        if (cambia) Cambio?.Invoke();
    }

    private void AlTerminarVideo()
    {
        if (!EsVideo) return;
        // Un final que llega justo después de lanzar otra pieza pertenece a la anterior.
        if ((DateTime.UtcNow - ultimoLanzamiento).TotalMilliseconds < 700) return;
        VolverAlFondo();
    }

    private void AlFallarVideo()
    {
        if (!EsVideo) return;
        var nombre = EnPantalla?.Nombre ?? "";
        VolverAlFondo();
        Aviso = $"No se pudo reproducir «{nombre}». La pantalla del público ha quedado en negro.";
        Cambio?.Invoke();
    }

    /// Las órdenes a VLC se ejecutan de una en una y en orden, fuera del hilo de la interfaz.
    private void Encolar(Action orden)
    {
        lock (candado)
        {
            if (cerrado) return;
            cola = cola.ContinueWith(_ =>
            {
                try { orden(); }
                catch { /* una orden fallida no debe detener la cola */ }
            }, TaskScheduler.Default);
        }
    }

    public void Dispose()
    {
        lock (candado)
        {
            if (cerrado) return;
            cerrado = true;
        }
        reloj.Stop();
        try
        {
            cola.Wait(1500);
            Reproductor?.Stop();
            Reproductor?.Dispose();
            vlc?.Dispose();
        }
        catch
        {
            // Al salir no hay nada más que hacer.
        }
    }
}
