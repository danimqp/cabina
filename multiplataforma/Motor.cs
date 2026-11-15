using Avalonia.Media.Imaging;
using Avalonia.Threading;
using LibVLCSharp.Shared;

namespace Proyectapp;

public enum Contenido { Fondo, Video, Imagen }

/// Resultado de comprobar una pieza antes de la función.
public sealed record Problema(string Texto, bool Grave);

public sealed record SalidaDeSonido(string Id, string Nombre);

/// Estado y lógica de la función: lista, reproducción, negro, música y guardado.
/// Todo el estado se lee y se cambia desde el hilo de la interfaz; las órdenes al motor VLC
/// van por colas propias para que nunca bloqueen los controles.
public sealed class Motor : IDisposable
{
    public Funcion Funcion { get; private set; } = new();
    public List<Pieza> Piezas => Funcion.Piezas;

    public Contenido Contenido { get; private set; } = Contenido.Fondo;
    public Pieza? EnPantalla { get; private set; }
    public Pieza? UltimaLanzada { get; private set; }
    public Bitmap? ImagenVisible { get; private set; }
    public Bitmap? Previa { get; private set; }
    public bool EsMensaje { get; private set; }
    public bool Negro { get; private set; }
    public bool Reproduciendo { get; private set; }
    public double Tiempo { get; private set; }
    public double Duracion { get; private set; }
    public string TituloEnPantalla { get; private set; } = "";
    public string? Aviso { get; set; }
    public string? Nota { get; private set; }
    public string? ErrorDeMotor { get; }
    public Guid? Seleccion { get; set; }
    public bool Comprobando { get; private set; }
    public bool Copiando { get; private set; }

    public HashSet<Guid> Faltantes { get; private set; } = new();
    public Dictionary<Guid, Problema> Problemas { get; private set; } = new();
    public Dictionary<Guid, Bitmap> MiniaturasDeLista { get; } = new();

    public bool MusicaEncendida { get; private set; }
    public string PistaMusica { get; private set; } = "";
    public List<SalidaDeSonido> Dispositivos { get; private set; } = new();
    public string? SalidaAudio { get; private set; }

    /// El reproductor de VLC de la salida; es nulo si el motor no se pudo cargar.
    public MediaPlayer? Reproductor { get; }
    public LibVLC? Vlc { get; }

    /// Cambió el estado (tiempo, negro, contenido…).
    public event Action? Cambio;

    /// Cambió la lista (piezas, orden, duraciones, marcas, miniaturas).
    public event Action? CambioDeLista;

    /// La ventana de control la define: abre la salida si hace falta y dice si ya estaba lista.
    public Func<bool>? AsegurarSalida { get; set; }

    private readonly MediaPlayer? musica;
    private readonly DispatcherTimer reloj;
    private readonly DispatcherTimer guardado;
    private readonly bool persistir;
    private readonly Cola colaVideo = new();
    private readonly Cola colaMusica = new();
    private Bitmap? imagenFondo;
    private bool reanudarTrasNegro;
    private DateTime ultimoLanzamiento = DateTime.MinValue;
    private double? finActual;
    private int turno;
    private int tics;
    private int indiceMusica;
    private bool musicaSonando;
    private DispatcherTimer? relojCuenta;
    private readonly HashSet<Guid> sinMiniatura = new();
    private bool generandoMiniaturas;
    private int turnoComprobar;
    private bool cerrado;
    private readonly string carpetaTemporal = Path.Combine(Path.GetTempPath(), "Proyectapp");

    public Motor(bool persistir = true)
    {
        this.persistir = persistir;
        try
        {
            Plataforma.CargarVlc();
            Vlc = new LibVLC("--no-video-title-show", "--no-osd", "--no-snapshot-preview", "--quiet");
            Reproductor = new MediaPlayer(Vlc) { EnableKeyInput = false, EnableMouseInput = false };
            Reproductor.EndReached += (_, _) => Dispatcher.UIThread.Post(AlTerminarVideo);
            Reproductor.EncounteredError += (_, _) => Dispatcher.UIThread.Post(AlFallarVideo);
            musica = new MediaPlayer(Vlc);
            musica.EndReached += (_, _) => Dispatcher.UIThread.Post(SiguientePista);
            musica.EncounteredError += (_, _) => Dispatcher.UIThread.Post(SiguientePista);
        }
        catch (Exception error)
        {
            ErrorDeMotor = "No se pudo cargar el motor de vídeo VLC: " + error.Message;
            Aviso = ErrorDeMotor;
        }

        try { Directory.CreateDirectory(carpetaTemporal); } catch { /* sin vista previa de vídeo */ }

        guardado = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        guardado.Tick += (_, _) =>
        {
            guardado.Stop();
            GuardarAhora();
        };

        if (persistir)
        {
            try
            {
                if (File.Exists(ArchivoAutomatico)) Funcion = Funcion.DeJson(File.ReadAllText(ArchivoAutomatico));
            }
            catch
            {
                Funcion = new Funcion();
            }
            SalidaAudio = LeerPreferencia("salidaAudio");
        }
        CargarFondo();
        ImagenVisible = imagenFondo;
        ActualizarDispositivos();
        VerificarArchivos();
        CargarDuraciones();
        Comprobar(avisar: false);

        reloj = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        reloj.Tick += (_, _) => Tic();
        reloj.Start();
    }

    // =====================================================================
    // Consultas
    // =====================================================================

    public bool EsVideo => Contenido == Contenido.Video;
    public bool EsImagen => Contenido == Contenido.Imagen;
    public bool HayFondo => imagenFondo != null;
    public bool MusicaSonando => musicaSonando;

    /// Segundo en el que termina la proyección del vídeo en pantalla (su final o su marca de fin).
    private double Limite => finActual is { } f && Duracion > 0 ? Math.Min(f, Duracion) : finActual ?? Duracion;

    public double Restante => Math.Max(0, Limite - Tiempo);

    public bool HayQueConfirmarCorte => EsVideo && Reproduciendo && Restante > 3;

    public Pieza? Siguiente
    {
        get
        {
            if (Piezas.Count == 0) return null;
            if (UltimaLanzada == null) return Piezas[0];
            var i = Piezas.IndexOf(UltimaLanzada);
            if (i < 0) return Piezas[0];
            return i + 1 < Piezas.Count ? Piezas[i + 1] : null;
        }
    }

    public double DuracionTotal => Piezas.Sum(p => p.Duracion ?? 0);

    /// Segundos de vídeo que quedan por proyectar, contando lo que falta del actual.
    public double DuracionPorDelante =>
        Piezas.Where(p => !p.Pasada && p != EnPantalla).Sum(p => p.Duracion ?? 0) + (EsVideo ? Restante : 0);

    public double VolumenActual => EsVideo && EnPantalla?.Volumen is { } propio ? propio : Funcion.Volumen;
    public bool VolumenEsDeLaPieza => EsVideo && EnPantalla != null && Piezas.Contains(EnPantalla);

    private void Avisar() => Cambio?.Invoke();

    private void AvisarLista()
    {
        CambioDeLista?.Invoke();
        Cambio?.Invoke();
    }

    // =====================================================================
    // Lanzar
    // =====================================================================

    /// Lanza la pieza. `desde` permite seguir un vídeo donde se cortó.
    public void Lanzar(Pieza pieza, double? desde = null)
    {
        if (!Piezas.Contains(pieza)) return;
        if (pieza.Tipo != TipoPieza.Texto && !Formatos.EsArchivoNormal(pieza.Ruta))
        {
            Faltantes.Add(pieza.Id);
            Aviso = $"No se encuentra el archivo de «{pieza.Nombre}». El proyector no ha cambiado. Usa «Localizar archivo…» en el menú de la pieza.";
            AvisarLista();
            return;
        }
        Faltantes.Remove(pieza.Id);

        switch (pieza.Tipo)
        {
            case TipoPieza.Video:
                if (Reproductor == null || Vlc == null)
                {
                    Aviso = ErrorDeMotor ?? "El motor de vídeo no está disponible.";
                    Avisar();
                    return;
                }
                // VLC necesita que la ventana de salida exista antes de reproducir; si no, abriría una ventana propia.
                if (AsegurarSalida != null && !AsegurarSalida())
                {
                    Dispatcher.UIThread.Post(() => Lanzar(pieza, desde), DispatcherPriority.Background);
                    return;
                }
                turno++;
                DejarLaActual();
                var arranque = Math.Max(0, desde ?? pieza.Inicio ?? 0);
                finActual = pieza.Fin is { } fin && fin > arranque + 1 ? fin : null;
                var ruta = pieza.Ruta;
                var subtitulos = pieza.Subtitulos != null && Formatos.EsArchivoNormal(pieza.Subtitulos, 5_000_000) ? pieza.Subtitulos : null;
                var volumen = (int)Math.Round((pieza.Volumen ?? Funcion.Volumen) * 100);
                var corte = finActual;
                var reproductor = Reproductor;
                var motorVlc = Vlc;
                colaVideo.Encolar(() =>
                {
                    using var medio = new Media(motorVlc, ruta, FromType.FromPath);
                    if (arranque > 0) medio.AddOption(FormattableString.Invariant($":start-time={arranque:0.###}"));
                    if (corte is { } hasta) medio.AddOption(FormattableString.Invariant($":stop-time={hasta:0.###}"));
                    if (subtitulos != null) medio.AddOption(":sub-file=" + subtitulos);
                    reproductor.Play(medio);
                    reproductor.Volume = volumen;
                });
                ImagenVisible = null;
                Previa = null;
                Contenido = Contenido.Video;
                EsMensaje = false;
                Tiempo = arranque;
                Duracion = pieza.Duracion ?? 0;
                Reproduciendo = true;
                ultimoLanzamiento = DateTime.UtcNow;
                CallarMusica();
                RematarLanzamiento(pieza);
                break;

            case TipoPieza.Imagen:
                // La imagen se abre fuera del hilo de la interfaz para no congelar los controles.
                var miTurno = ++turno;
                var rutaImagen = pieza.Ruta;
                _ = Task.Run(() => Miniaturas.ImagenReducida(rutaImagen, 3840)).ContinueWith(tarea =>
                {
                    Dispatcher.UIThread.Post(() =>
                    {
                        if (turno != miTurno || !Piezas.Contains(pieza)) return;
                        var imagen = tarea.IsCompletedSuccessfully ? tarea.Result : null;
                        if (imagen == null)
                        {
                            Aviso = $"No se pudo abrir la imagen «{pieza.Nombre}». El proyector no ha cambiado.";
                            Avisar();
                            return;
                        }
                        PonerImagen(imagen, mensaje: false);
                        RematarLanzamiento(pieza);
                    });
                });
                break;

            case TipoPieza.Texto:
                turno++;
                PonerImagen(Rotulo.Imagen(pieza.Texto ?? pieza.Nombre), mensaje: true);
                RematarLanzamiento(pieza);
                break;
        }
    }

    private void RematarLanzamiento(Pieza pieza)
    {
        EnPantalla = pieza;
        UltimaLanzada = pieza;
        TituloEnPantalla = pieza.Nombre;
        pieza.Pasada = false;
        reanudarTrasNegro = false;
        Negro = false;
        Aviso = null;
        AvisarLista();
    }

    public void LanzarSiguiente()
    {
        var siguiente = Siguiente;
        if (siguiente != null) Lanzar(siguiente, siguiente.Posicion);
    }

    /// Muestra un mensaje escrito al momento, sin añadirlo a la lista.
    public void MostrarMensaje(string texto)
    {
        var limpio = texto.Trim();
        if (limpio.Length == 0) return;
        turno++;
        PonerImagen(Rotulo.Imagen(limpio), mensaje: true);
        EnPantalla = null;
        TituloEnPantalla = limpio;
        reanudarTrasNegro = false;
        Negro = false;
        AvisarLista();
    }

    /// Muestra en la salida una cuenta atrás que se actualiza sola.
    public void IniciarCuenta(int segundos, string titulo)
    {
        var cabecera = string.IsNullOrWhiteSpace(titulo) ? "Empezamos en" : titulo.Trim();
        var final = DateTime.UtcNow.AddSeconds(segundos);
        var ultimo = cabecera + "\n" + Formatos.Tiempo(segundos);
        var miTurno = ++turno;
        PonerImagen(Rotulo.Imagen(ultimo, cifrasFijas: true), mensaje: true);
        EnPantalla = null;
        TituloEnPantalla = "Cuenta atrás · " + cabecera;
        reanudarTrasNegro = false;
        Negro = false;
        var temporizador = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        temporizador.Tick += (_, _) =>
        {
            if (turno != miTurno)
            {
                temporizador.Stop();
                return;
            }
            var quedan = Math.Max(0, (final - DateTime.UtcNow).TotalSeconds);
            var texto = cabecera + "\n" + (quedan > 0 ? Formatos.Tiempo(Math.Ceiling(quedan)) : "00:00");
            if (texto != ultimo)
            {
                ultimo = texto;
                ImagenVisible = Rotulo.Imagen(texto, cifrasFijas: true);
                Avisar();
            }
            if (quedan <= 0) temporizador.Stop();
        };
        relojCuenta = temporizador;
        temporizador.Start();
        AvisarLista();
    }

    private void PonerImagen(Bitmap imagen, bool mensaje)
    {
        DejarLaActual();
        DetenerVideo();
        finActual = null;
        ImagenVisible = imagen;
        Previa = null;
        Contenido = Contenido.Imagen;
        EsMensaje = mensaje;
        Tiempo = 0;
        Duracion = 0;
        Reproduciendo = false;
        RetomarMusica();
    }

    /// Retira la pieza y deja la imagen de fondo (o negro).
    public void VolverAlFondo() => Retirar(terminada: false);

    private void Retirar(bool terminada)
    {
        turno++;
        Pieza? encadenada = null;
        if (terminada && EsVideo && EnPantalla is { } actual && Piezas.Contains(actual))
        {
            actual.Posicion = null;
            actual.Pasada = true;
            if (actual.Encadena == true)
            {
                var i = Piezas.IndexOf(actual);
                if (i + 1 < Piezas.Count) encadenada = Piezas[i + 1];
            }
            GuardarPronto();
        }
        else
        {
            DejarLaActual();
        }
        DetenerVideo();
        finActual = null;
        ImagenVisible = imagenFondo;
        Previa = null;
        Contenido = Contenido.Fondo;
        EnPantalla = null;
        EsMensaje = false;
        Reproduciendo = false;
        reanudarTrasNegro = false;
        Tiempo = 0;
        Duracion = 0;
        TituloEnPantalla = "";
        if (encadenada != null)
        {
            Lanzar(encadenada);
            if (EnPantalla == encadenada || encadenada.Tipo == TipoPieza.Imagen) return;
        }
        RetomarMusica();
        AvisarLista();
    }

    /// Antes de cambiar de pieza: marca la actual como pasada y recuerda por dónde iba.
    private void DejarLaActual()
    {
        relojCuenta?.Stop();
        relojCuenta = null;
        GuardarPosicionActual();
        if (EnPantalla != null && Piezas.Contains(EnPantalla)) EnPantalla.Pasada = true;
    }

    /// Recuerda el punto del vídeo en marcha para poder seguir desde ahí tras un corte.
    private void GuardarPosicionActual()
    {
        if (!EsVideo || EnPantalla is not { } pieza || !Piezas.Contains(pieza) || Duracion <= 0) return;
        var t = Tiempo;
        var guardada = pieza.Posicion;
        if (Limite - t <= 5)
        {
            if (guardada != null)
            {
                pieza.Posicion = null;
                GuardarPronto();
            }
        }
        else if (t > 5 && (guardada == null || t > guardada || t > 30))
        {
            pieza.Posicion = t;
            GuardarPronto();
        }
    }

    private void DetenerVideo()
    {
        var reproductor = Reproductor;
        if (reproductor == null) return;
        colaVideo.Encolar(() => reproductor.Stop());
    }

    // =====================================================================
    // Transporte
    // =====================================================================

    public void AlternarPausa()
    {
        if (!EsVideo || Reproductor == null) return;
        var reproductor = Reproductor;
        if (Reproduciendo)
        {
            colaVideo.Encolar(() => reproductor.SetPause(true));
            Reproduciendo = false;
        }
        else
        {
            reanudarTrasNegro = false;
            Negro = false;
            var volumen = (int)Math.Round(VolumenActual * 100);
            colaVideo.Encolar(() =>
            {
                reproductor.Volume = volumen;
                reproductor.SetPause(false);
            });
            Reproduciendo = true;
        }
        Avisar();
    }

    public void AlternarNegro()
    {
        var reproductor = Reproductor;
        var volumen = (int)Math.Round(VolumenActual * 100);
        if (Negro)
        {
            Negro = false;
            if (reanudarTrasNegro && EsVideo && reproductor != null)
            {
                colaVideo.Encolar(() =>
                {
                    reproductor.Volume = volumen;
                    reproductor.SetPause(false);
                });
                Reproduciendo = true;
            }
            reanudarTrasNegro = false;
        }
        else
        {
            reanudarTrasNegro = EsVideo && Reproduciendo;
            if (reanudarTrasNegro && reproductor != null)
            {
                // El sonido baja en un cuarto de segundo antes de detenerse, para que el negro no suene a corte.
                colaVideo.Encolar(() =>
                {
                    for (var paso = 4; paso >= 0; paso--)
                    {
                        reproductor.Volume = volumen * paso / 5;
                        Thread.Sleep(45);
                    }
                    reproductor.SetPause(true);
                    reproductor.Volume = volumen;
                });
            }
            Reproduciendo = false;
            Negro = true;
        }
        Avisar();
    }

    public void Buscar(double segundos)
    {
        if (!EsVideo || Reproductor == null || Duracion <= 0) return;
        var destino = Math.Clamp(segundos, 0, Math.Max(0, Limite - 0.3));
        var reproductor = Reproductor;
        colaVideo.Encolar(() => reproductor.Time = (long)(destino * 1000));
        Tiempo = destino;
        Avisar();
    }

    /// Con un vídeo en pantalla ajusta y recuerda el volumen de ese vídeo; si no, el general.
    public void FijarVolumen(double valor)
    {
        var v = Math.Clamp(valor, 0, 1);
        if (EsVideo && EnPantalla is { } pieza && Piezas.Contains(pieza)) pieza.Volumen = v;
        else Funcion.Volumen = v;
        var reproductor = Reproductor;
        var entero = (int)Math.Round(v * 100);
        if (reproductor != null) colaVideo.Encolar(() => reproductor.Volume = entero);
        GuardarPronto();
        Avisar();
    }

    private void Tic()
    {
        if (!EsVideo || Reproductor == null) return;
        tics++;
        var ms = Reproductor.Time;
        var largo = Reproductor.Length;
        var cambia = false;
        if (!Negro && Reproduciendo && ms >= 0 && Math.Abs(ms / 1000.0 - Tiempo) > 0.05)
        {
            Tiempo = ms / 1000.0;
            cambia = true;
        }
        if (largo > 0 && Math.Abs(largo / 1000.0 - Duracion) > 0.05)
        {
            Duracion = largo / 1000.0;
            cambia = true;
        }
        if (tics % 25 == 0) GuardarPosicionActual();
        if (tics % 6 == 0 && Reproduciendo && !Negro) PedirInstantanea();
        if (cambia) Avisar();
    }

    /// Fotograma actual para la vista previa del operador, más o menos una vez por segundo.
    private void PedirInstantanea()
    {
        var reproductor = Reproductor;
        if (reproductor == null) return;
        var miTurno = turno;
        var destino = Path.Combine(carpetaTemporal, "previa.png");
        colaVideo.Encolar(() =>
        {
            try
            {
                try { File.Delete(destino); } catch { /* se sobrescribe */ }
                if (!reproductor.TakeSnapshot(0, destino, 480, 0)) return;
                // VLC escribe el archivo un instante después de aceptar la orden.
                byte[]? datos = null;
                for (var intento = 0; intento < 12 && datos == null; intento++)
                {
                    Thread.Sleep(80);
                    try
                    {
                        if (File.Exists(destino) && new FileInfo(destino).Length > 0) datos = File.ReadAllBytes(destino);
                    }
                    catch
                    {
                        datos = null;
                    }
                }
                if (datos == null) return;
                var imagen = new Bitmap(new MemoryStream(datos));
                Dispatcher.UIThread.Post(() =>
                {
                    if (turno != miTurno || !EsVideo) return;
                    Previa = imagen;
                    Avisar();
                });
            }
            catch
            {
                // Sin instantánea esta vez; se reintenta en un segundo.
            }
        });
    }

    private void AlTerminarVideo()
    {
        if (!EsVideo) return;
        // Un final que llega justo después de lanzar otra pieza pertenece a la anterior.
        if ((DateTime.UtcNow - ultimoLanzamiento).TotalMilliseconds < 700) return;
        Retirar(terminada: true);
    }

    private void AlFallarVideo()
    {
        if (!EsVideo) return;
        var nombre = TituloEnPantalla;
        VolverAlFondo();
        Aviso = $"No se pudo reproducir «{nombre}»: el formato no es compatible o el archivo ya no está. El proyector ha vuelto al fondo.";
        Avisar();
    }

    // =====================================================================
    // Sonido
    // =====================================================================

    public void ActualizarDispositivos()
    {
        if (Reproductor == null) return;
        try
        {
            Dispositivos = Reproductor.AudioOutputDeviceEnum
                .Where(d => !string.IsNullOrEmpty(d.DeviceIdentifier) && !string.IsNullOrEmpty(d.Description))
                .Select(d => new SalidaDeSonido(d.DeviceIdentifier, d.Description))
                .ToList();
        }
        catch
        {
            Dispositivos = new();
        }
        if (SalidaAudio != null)
        {
            if (Dispositivos.Any(d => d.Id == SalidaAudio)) AplicarSalidaAudio(SalidaAudio);
            else SalidaAudio = null;
        }
    }

    public void ElegirSalidaAudio(string? id)
    {
        SalidaAudio = id;
        AplicarSalidaAudio(id);
        if (persistir) GuardarPreferencia("salidaAudio", id);
        Avisar();
    }

    private void AplicarSalidaAudio(string? id)
    {
        var video = Reproductor;
        var espera = musica;
        if (video == null) return;
        colaVideo.Encolar(() =>
        {
            video.SetOutputDevice(id ?? "");
            espera?.SetOutputDevice(id ?? "");
        });
    }

    // =====================================================================
    // Música de espera
    // =====================================================================

    public void FijarMusica(IEnumerable<string> rutas)
    {
        Funcion.Musica = rutas.Where(r => Formatos.Audio.Contains(Formatos.Extension(r)))
            .OrderBy(r => Path.GetFileName(r), StringComparer.CurrentCultureIgnoreCase).ToList();
        indiceMusica = 0;
        PistaMusica = "";
        var espera = musica;
        if (espera != null) colaMusica.Encolar(() => espera.Stop());
        musicaSonando = false;
        GuardarPronto();
        Avisar();
    }

    public void AlternarMusica()
    {
        if (MusicaEncendida) ApagarMusica(); else EncenderMusica();
    }

    public void EncenderMusica()
    {
        if (Funcion.Musica.Count == 0 || musica == null) return;
        MusicaEncendida = true;
        RetomarMusica();
        Avisar();
    }

    public void ApagarMusica()
    {
        MusicaEncendida = false;
        CallarMusica();
        Avisar();
    }

    /// La música suena solo si está encendida y no hay un vídeo en pantalla.
    private void RetomarMusica()
    {
        if (!MusicaEncendida || EsVideo || musica == null || Vlc == null) return;
        if (musicaSonando) return;
        var ruta = SiguienteRutaDeMusica();
        if (ruta == null)
        {
            MusicaEncendida = false;
            Aviso = "No se encuentra ningún archivo de la música de espera.";
            return;
        }
        PistaMusica = Path.GetFileNameWithoutExtension(ruta);
        musicaSonando = true;
        var espera = musica;
        var motorVlc = Vlc;
        var destino = (int)Math.Round(Funcion.VolumenMusica * 100);
        colaMusica.Encolar(() =>
        {
            using var medio = new Media(motorVlc, ruta, FromType.FromPath);
            espera.Volume = 0;
            espera.Play(medio);
            for (var paso = 1; paso <= 8; paso++)
            {
                Thread.Sleep(90);
                espera.Volume = destino * paso / 8;
            }
        });
    }

    private void CallarMusica()
    {
        if (!musicaSonando || musica == null) return;
        musicaSonando = false;
        var espera = musica;
        colaMusica.Encolar(() =>
        {
            var inicio = Math.Max(0, espera.Volume);
            for (var paso = 7; paso >= 0; paso--)
            {
                espera.Volume = inicio * paso / 8;
                Thread.Sleep(90);
            }
            espera.Stop();
        });
    }

    private string? SiguienteRutaDeMusica()
    {
        var rutas = Funcion.Musica;
        for (var salto = 0; salto < rutas.Count; salto++)
        {
            var i = (indiceMusica + salto) % rutas.Count;
            if (!Formatos.EsArchivoNormal(rutas[i])) continue;
            indiceMusica = i;
            return rutas[i];
        }
        return null;
    }

    private void SiguientePista()
    {
        if (!musicaSonando) return;
        musicaSonando = false;
        indiceMusica++;
        RetomarMusica();
        Avisar();
    }

    public void FijarVolumenMusica(double valor)
    {
        Funcion.VolumenMusica = Math.Clamp(valor, 0, 1);
        var espera = musica;
        var entero = (int)Math.Round(Funcion.VolumenMusica * 100);
        if (espera != null && musicaSonando) colaMusica.Encolar(() => espera.Volume = entero);
        GuardarPronto();
        Avisar();
    }

    // =====================================================================
    // Lista
    // =====================================================================

    public int Agregar(IEnumerable<string> rutas)
    {
        var entrada = rutas.ToList();
        var nuevas = new List<Pieza>();
        foreach (var ruta in entrada.OrderBy(r => Path.GetFileName(r), StringComparer.CurrentCultureIgnoreCase))
        {
            var tipo = Formatos.TipoDeArchivo(ruta);
            if (tipo == null) continue;
            var pieza = new Pieza { Nombre = Path.GetFileNameWithoutExtension(ruta), Ruta = ruta, Tipo = tipo.Value };
            if (tipo == TipoPieza.Video)
            {
                var srt = Path.ChangeExtension(ruta, ".srt");
                if (File.Exists(srt)) pieza.Subtitulos = srt;
            }
            nuevas.Add(pieza);
        }
        Piezas.AddRange(nuevas);
        var ajenos = entrada.Count(r => Formatos.TipoDeArchivo(r) == null && Formatos.Extension(r) != "srt");
        if (ajenos > 0) Aviso = $"{ajenos} archivo(s) no se añadieron: no son vídeos ni imágenes que Proyectapp reconozca.";
        if (Nota != null) Nota = null;
        CargarDuraciones();
        Comprobar(avisar: false);
        GuardarPronto();
        AvisarLista();
        return nuevas.Count;
    }

    /// Guarda un mensaje de texto como pieza de la lista, para reutilizarlo.
    public void AgregarMensaje(string texto)
    {
        var limpio = texto.Trim();
        if (limpio.Length == 0) return;
        Piezas.Add(Pieza.Mensaje(limpio));
        GuardarPronto();
        AvisarLista();
    }

    public void Quitar(Pieza pieza)
    {
        var i = Piezas.IndexOf(pieza);
        if (i < 0) return;
        if (UltimaLanzada == pieza) UltimaLanzada = i > 0 ? Piezas[i - 1] : null;
        Piezas.RemoveAt(i);
        MiniaturasDeLista.Remove(pieza.Id);
        sinMiniatura.Remove(pieza.Id);
        Faltantes.Remove(pieza.Id);
        Problemas.Remove(pieza.Id);
        if (Seleccion == pieza.Id) Seleccion = null;
        GuardarPronto();
        AvisarLista();
    }

    public void Mover(Pieza pieza, int salto)
    {
        var i = Piezas.IndexOf(pieza);
        var j = i + salto;
        if (i < 0 || j < 0 || j >= Piezas.Count) return;
        Piezas.RemoveAt(i);
        Piezas.Insert(j, pieza);
        GuardarPronto();
        AvisarLista();
    }

    public void Renombrar(Pieza pieza, string nombre)
    {
        var limpio = nombre.Trim();
        if (limpio.Length == 0 || !Piezas.Contains(pieza)) return;
        pieza.Nombre = limpio.Length > 300 ? limpio[..300] : limpio;
        if (pieza.Tipo == TipoPieza.Texto)
        {
            pieza.Texto = limpio;
            MiniaturasDeLista.Remove(pieza.Id);
            if (EnPantalla == pieza) ImagenVisible = Rotulo.Imagen(limpio);
        }
        if (EnPantalla == pieza) TituloEnPantalla = pieza.Nombre;
        GuardarPronto();
        AvisarLista();
    }

    public void Relocalizar(Pieza pieza, string ruta)
    {
        var tipo = Formatos.TipoDeArchivo(ruta);
        if (tipo == null || !Piezas.Contains(pieza)) return;
        pieza.Ruta = ruta;
        pieza.Tipo = tipo.Value;
        pieza.Duracion = null;
        pieza.Posicion = null;
        pieza.Inicio = null;
        pieza.Fin = null;
        pieza.Subtitulos = null;
        MiniaturasDeLista.Remove(pieza.Id);
        sinMiniatura.Remove(pieza.Id);
        CargarDuraciones();
        Comprobar(avisar: false);
        GuardarPronto();
        AvisarLista();
    }

    public void FijarSubtitulos(Pieza pieza, string? ruta)
    {
        if (!Piezas.Contains(pieza)) return;
        pieza.Subtitulos = ruta;
        GuardarPronto();
        AvisarLista();
    }

    public void OlvidarPosicion(Pieza pieza)
    {
        pieza.Posicion = null;
        GuardarPronto();
        AvisarLista();
    }

    /// Marca el punto actual del vídeo en pantalla como su comienzo en próximas proyecciones.
    public void MarcarInicio()
    {
        if (!EsVideo || EnPantalla is not { } pieza) return;
        if (pieza.Fin is { } fin && fin <= Tiempo + 1) pieza.Fin = null;
        pieza.Inicio = Tiempo > 0.5 ? Tiempo : null;
        GuardarPronto();
        AvisarLista();
    }

    /// Marca el punto actual como final: la próxima vez, la proyección terminará ahí.
    public void MarcarFin()
    {
        if (!EsVideo || EnPantalla is not { } pieza) return;
        if (Tiempo <= (pieza.Inicio ?? 0) + 1)
        {
            Aviso = "El final tiene que quedar después del comienzo.";
            Avisar();
            return;
        }
        pieza.Fin = Tiempo;
        GuardarPronto();
        AvisarLista();
    }

    public void QuitarRecorte(Pieza pieza)
    {
        pieza.Inicio = null;
        pieza.Fin = null;
        GuardarPronto();
        AvisarLista();
    }

    public void AlternarEncadenado(Pieza pieza)
    {
        pieza.Encadena = pieza.Encadena == true ? null : true;
        GuardarPronto();
        AvisarLista();
    }

    public void FijarNombreDeFuncion(string nombre)
    {
        Funcion.Nombre = nombre.Length > 200 ? nombre[..200] : nombre;
        GuardarPronto();
    }

    // =====================================================================
    // Duraciones, miniaturas y previsualización
    // =====================================================================

    private void CargarDuraciones()
    {
        if (Vlc == null) return;
        foreach (var pieza in Piezas.Where(p => p.Tipo == TipoPieza.Video && p.Duracion == null).ToList())
        {
            var motorVlc = Vlc;
            _ = Task.Run(async () =>
            {
                var datos = await Miniaturas.Datos(motorVlc, pieza.Ruta);
                if (datos.Duracion <= 0) return;
                Dispatcher.UIThread.Post(() =>
                {
                    pieza.Duracion = datos.Duracion;
                    GuardarPronto();
                    AvisarLista();
                });
            });
        }
        GenerarMiniaturas();
    }

    /// Genera las miniaturas que falten, de una en una y fuera del hilo de la interfaz.
    private async void GenerarMiniaturas()
    {
        if (generandoMiniaturas) return;
        generandoMiniaturas = true;
        try
        {
            while (!cerrado)
            {
                var pieza = Piezas.FirstOrDefault(p => !MiniaturasDeLista.ContainsKey(p.Id) && !sinMiniatura.Contains(p.Id));
                if (pieza == null) break;
                Bitmap? imagen = null;
                var ruta = pieza.Ruta;
                try
                {
                    if (pieza.Tipo == TipoPieza.Texto)
                    {
                        imagen = Rotulo.Imagen(pieza.Texto ?? pieza.Nombre).CreateScaledBitmap(new Avalonia.PixelSize(320, 180));
                    }
                    else if (pieza.Tipo == TipoPieza.Imagen)
                    {
                        imagen = await Task.Run(() => Miniaturas.ImagenReducida(ruta, 320));
                    }
                    else if (Vlc != null)
                    {
                        var motorVlc = Vlc;
                        imagen = await Task.Run(async () =>
                        {
                            var datos = await Miniaturas.Datos(motorVlc, ruta);
                            return await Miniaturas.Fotograma(motorVlc, ruta, datos.Duracion * 0.1, datos, 320);
                        });
                    }
                }
                catch
                {
                    imagen = null;
                }
                if (imagen != null && Piezas.Contains(pieza) && pieza.Ruta == ruta) MiniaturasDeLista[pieza.Id] = imagen;
                else sinMiniatura.Add(pieza.Id);
                CambioDeLista?.Invoke();
            }
        }
        finally
        {
            generandoMiniaturas = false;
        }
    }

    /// Cinco fotogramas repartidos por el vídeo (o la imagen entera) y sus datos técnicos.
    public async Task<(List<(double? Segundo, Bitmap Imagen)> Fotogramas, string Detalle)> PreviaDe(Pieza pieza)
    {
        var lista = new List<(double?, Bitmap)>();
        switch (pieza.Tipo)
        {
            case TipoPieza.Texto:
                lista.Add((null, Rotulo.Imagen(pieza.Texto ?? pieza.Nombre)));
                return (lista, "Mensaje de texto");
            case TipoPieza.Imagen:
                var imagen = await Task.Run(() => Miniaturas.ImagenReducida(pieza.Ruta, 900));
                if (imagen != null) lista.Add((null, imagen));
                return (lista, imagen == null ? "Imagen" : "Imagen");
            default:
                if (Vlc == null) return (lista, "");
                var motorVlc = Vlc;
                var ruta = pieza.Ruta;
                return await Task.Run(async () =>
                {
                    var datos = await Miniaturas.Datos(motorVlc, ruta);
                    foreach (var fraccion in new[] { 0.04, 0.27, 0.5, 0.73, 0.93 })
                    {
                        var segundo = datos.Duracion * fraccion;
                        var cuadro = await Miniaturas.Fotograma(motorVlc, ruta, segundo, datos, 480);
                        if (cuadro != null) lista.Add((segundo, cuadro));
                    }
                    return (lista, datos.Detalle);
                });
        }
    }

    // =====================================================================
    // Comprobar la función
    // =====================================================================

    public void VerificarArchivos()
    {
        var pares = Piezas.Where(p => p.Tipo != TipoPieza.Texto).Select(p => (p.Id, p.Ruta)).ToList();
        _ = Task.Run(() => pares.Where(par => !Formatos.EsArchivoNormal(par.Ruta)).Select(par => par.Id).ToHashSet())
            .ContinueWith(tarea =>
            {
                if (!tarea.IsCompletedSuccessfully) return;
                Dispatcher.UIThread.Post(() =>
                {
                    var vigentes = Piezas.Select(p => p.Id).ToHashSet();
                    var nuevos = tarea.Result.Where(vigentes.Contains).ToHashSet();
                    if (nuevos.SetEquals(Faltantes)) return;
                    Faltantes = nuevos;
                    AvisarLista();
                });
            });
    }

    /// Abre cada archivo para detectar, antes de proyectar, los que no van a funcionar.
    public void Comprobar(bool avisar)
    {
        var miTurno = ++turnoComprobar;
        var piezas = Piezas.Where(p => p.Tipo != TipoPieza.Texto).Select(p => (p.Id, p.Ruta, p.Tipo)).ToList();
        if (avisar)
        {
            Comprobando = true;
            Nota = null;
            Avisar();
        }
        var motorVlc = Vlc;
        _ = Task.Run(async () =>
        {
            var hallados = new Dictionary<Guid, Problema>();
            var faltan = new HashSet<Guid>();
            foreach (var (id, ruta, tipo) in piezas)
            {
                if (!Formatos.EsArchivoNormal(ruta))
                {
                    faltan.Add(id);
                    continue;
                }
                if (tipo == TipoPieza.Video && motorVlc != null)
                {
                    var datos = await Miniaturas.Datos(motorVlc, ruta);
                    if (!datos.Legible || !datos.ConImagen) hallados[id] = new Problema("ESTE VÍDEO NO SE PUEDE REPRODUCIR", true);
                    else if (!datos.ConSonido) hallados[id] = new Problema("Sin sonido", false);
                }
                else if (tipo == TipoPieza.Imagen && Miniaturas.ImagenReducida(ruta, 64) == null)
                {
                    hallados[id] = new Problema("ESTA IMAGEN NO SE PUEDE ABRIR", true);
                }
            }
            Dispatcher.UIThread.Post(() =>
            {
                if (miTurno != turnoComprobar) return;
                var vigentes = Piezas.Select(p => p.Id).ToHashSet();
                Problemas = hallados.Where(par => vigentes.Contains(par.Key)).ToDictionary(par => par.Key, par => par.Value);
                Faltantes = faltan.Where(vigentes.Contains).ToHashSet();
                Comprobando = false;
                if (avisar)
                {
                    var graves = Problemas.Values.Count(p => p.Grave) + Faltantes.Count;
                    var mudos = Problemas.Values.Count(p => !p.Grave);
                    if (graves > 0)
                    {
                        Nota = null;
                        Aviso = $"{graves} pieza(s) no se van a poder proyectar. Están marcadas en rojo en la lista.";
                    }
                    else
                    {
                        Nota = mudos > 0
                            ? $"Comprobado: todo se puede proyectar. {mudos} vídeo(s) sin sonido."
                            : "Comprobado: todo listo para proyectar.";
                    }
                }
                AvisarLista();
            });
        });
    }

    // =====================================================================
    // Fondo
    // =====================================================================

    public void FijarFondo(string? ruta)
    {
        Funcion.RutaFondo = ruta;
        CargarFondo();
        if (Contenido == Contenido.Fondo) ImagenVisible = imagenFondo;
        GuardarPronto();
        Avisar();
    }

    private void CargarFondo()
    {
        imagenFondo = null;
        var ruta = Funcion.RutaFondo;
        if (ruta == null) return;
        imagenFondo = Miniaturas.ImagenReducida(ruta, 3840);
        if (imagenFondo == null) Aviso = "No se encuentra la imagen de fondo. Entre vídeos se verá negro.";
    }

    // =====================================================================
    // Guardar, abrir y reunir
    // =====================================================================

    private static string CarpetaDeDatos =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Proyectapp");

    private static string ArchivoAutomatico => Path.Combine(CarpetaDeDatos, "funcion.json");

    public static string? LeerPreferencia(string nombre)
    {
        try
        {
            var archivo = Path.Combine(CarpetaDeDatos, nombre + ".txt");
            return File.Exists(archivo) ? File.ReadAllText(archivo).Trim() is { Length: > 0 } texto ? texto : null : null;
        }
        catch
        {
            return null;
        }
    }

    public static void GuardarPreferencia(string nombre, string? valor)
    {
        try
        {
            Directory.CreateDirectory(CarpetaDeDatos);
            File.WriteAllText(Path.Combine(CarpetaDeDatos, nombre + ".txt"), valor ?? "");
        }
        catch
        {
            // Preferencia no guardada: no afecta a la proyección.
        }
    }

    private void GuardarPronto()
    {
        if (!persistir) return;
        guardado.Stop();
        guardado.Start();
    }

    private void GuardarAhora()
    {
        if (!persistir) return;
        try
        {
            Directory.CreateDirectory(CarpetaDeDatos);
            var temporal = ArchivoAutomatico + ".tmp";
            File.WriteAllText(temporal, Funcion.AJson());
            File.Move(temporal, ArchivoAutomatico, overwrite: true);
        }
        catch
        {
            Aviso = "No se pudo guardar la función automáticamente.";
        }
    }

    public bool GuardarComo(string ruta)
    {
        try
        {
            File.WriteAllText(ruta, Funcion.AJson());
            return true;
        }
        catch
        {
            Aviso = "No se pudo guardar la función en esa ubicación.";
            Avisar();
            return false;
        }
    }

    public bool Abrir(string ruta)
    {
        try
        {
            if (!Formatos.EsArchivoNormal(ruta, 20_000_000)) throw new IOException();
            Reemplazar(Funcion.DeJson(File.ReadAllText(ruta)));
            return true;
        }
        catch
        {
            Aviso = "No se pudo abrir esa función: el archivo no es una función de Proyectapp.";
            Avisar();
            return false;
        }
    }

    public void Nueva() => Reemplazar(new Funcion());

    private void Reemplazar(Funcion nueva)
    {
        VolverAlFondo();
        ApagarMusica();
        indiceMusica = 0;
        PistaMusica = "";
        Negro = false;
        UltimaLanzada = null;
        Seleccion = null;
        MiniaturasDeLista.Clear();
        sinMiniatura.Clear();
        Problemas = new();
        Faltantes = new();
        Nota = null;
        Funcion = nueva;
        CargarFondo();
        ImagenVisible = imagenFondo;
        CargarDuraciones();
        Comprobar(avisar: false);
        GuardarPronto();
        AvisarLista();
    }

    /// Copia a una carpeta todos los archivos de la función, para no depender de un USB.
    public async Task Reunir(string carpeta)
    {
        if (Copiando) return;
        var medios = Formatos.Video.Concat(Formatos.Imagen).ToHashSet();
        var permitidas = new Dictionary<string, HashSet<string>>();
        void Permitir(string? ruta, IEnumerable<string> extensiones)
        {
            if (string.IsNullOrEmpty(ruta)) return;
            if (!permitidas.TryGetValue(ruta, out var conjunto)) permitidas[ruta] = conjunto = new HashSet<string>();
            conjunto.UnionWith(extensiones);
        }
        foreach (var pieza in Piezas.Where(p => p.Tipo != TipoPieza.Texto))
        {
            Permitir(pieza.Ruta, medios);
            Permitir(pieza.Subtitulos, new[] { "srt" });
        }
        Permitir(Funcion.RutaFondo, Formatos.Imagen);
        foreach (var ruta in Funcion.Musica) Permitir(ruta, Formatos.Audio);

        Copiando = true;
        Nota = $"Copiando {permitidas.Count} archivo(s)…";
        Avisar();
        var (mapa, fallos) = await Task.Run(() => Copiar(permitidas, carpeta));
        Copiando = false;

        foreach (var pieza in Piezas)
        {
            if (mapa.TryGetValue(pieza.Ruta, out var destino)) pieza.Ruta = destino;
            if (pieza.Subtitulos != null && mapa.TryGetValue(pieza.Subtitulos, out var sub)) pieza.Subtitulos = sub;
        }
        if (Funcion.RutaFondo != null && mapa.TryGetValue(Funcion.RutaFondo, out var fondo)) Funcion.RutaFondo = fondo;
        Funcion.Musica = Funcion.Musica.Select(r => mapa.TryGetValue(r, out var d) ? d : r).ToList();
        VerificarArchivos();
        GuardarPronto();

        var nombre = string.Join("-", (string.IsNullOrWhiteSpace(Funcion.Nombre) ? "Función" : Funcion.Nombre.Trim())
            .Split(Path.GetInvalidFileNameChars(), StringSplitOptions.RemoveEmptyEntries));
        var guardada = GuardarComo(Path.Combine(carpeta, nombre + ".proyectapp"));
        var etiqueta = Path.GetFileName(carpeta.TrimEnd(Path.DirectorySeparatorChar));
        if (!guardada)
        {
            Nota = null;
            Aviso = $"Los archivos se copiaron, pero no se pudo guardar la función en «{etiqueta}».";
        }
        else if (fallos > 0)
        {
            Nota = null;
            Aviso = $"{fallos} archivo(s) no se pudieron copiar (no se encontraron o no hay espacio). El resto está en «{etiqueta}».";
        }
        else
        {
            Nota = $"Archivos reunidos en «{etiqueta}»: la función ya no depende de otros discos.";
        }
        AvisarLista();
    }

    /// Solo copia archivos normales del tipo esperado: nunca carpetas ni otros documentos.
    private static (Dictionary<string, string> Mapa, int Fallos) Copiar(Dictionary<string, HashSet<string>> permitidas, string carpeta)
    {
        var mapa = new Dictionary<string, string>();
        var fallos = 0;
        var raiz = Path.GetFullPath(carpeta).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        foreach (var (ruta, extensiones) in permitidas)
        {
            try
            {
                var origen = Path.GetFullPath(ruta);
                if (origen.StartsWith(raiz, StringComparison.OrdinalIgnoreCase)) continue;
                if (!Formatos.EsArchivoNormal(origen) || !extensiones.Contains(Formatos.Extension(origen)))
                {
                    fallos++;
                    continue;
                }
                var tam = new FileInfo(origen).Length;
                var destino = Path.Combine(carpeta, Path.GetFileName(origen));
                var intento = 2;
                var reutilizar = false;
                while (File.Exists(destino))
                {
                    if (new FileInfo(destino).Length == tam)
                    {
                        reutilizar = true;
                        break;
                    }
                    destino = Path.Combine(carpeta, $"{Path.GetFileNameWithoutExtension(origen)} {intento}{Path.GetExtension(origen)}");
                    intento++;
                }
                if (!reutilizar) File.Copy(origen, destino);
                mapa[ruta] = destino;
            }
            catch
            {
                fallos++;
            }
        }
        return (mapa, fallos);
    }

    public void Dispose()
    {
        if (cerrado) return;
        cerrado = true;
        reloj.Stop();
        guardado.Stop();
        GuardarPosicionActual();
        GuardarAhora();
        try
        {
            colaVideo.Cerrar();
            colaMusica.Cerrar();
            Reproductor?.Stop();
            musica?.Stop();
            Reproductor?.Dispose();
            musica?.Dispose();
            Vlc?.Dispose();
        }
        catch
        {
            // Al salir no hay nada más que hacer.
        }
    }
}

/// Ejecuta órdenes de una en una y en orden, fuera del hilo de la interfaz.
public sealed class Cola
{
    private readonly object candado = new();
    private Task ultima = Task.CompletedTask;
    private bool cerrada;

    public void Encolar(Action orden)
    {
        lock (candado)
        {
            if (cerrada) return;
            ultima = ultima.ContinueWith(_ =>
            {
                try { orden(); }
                catch { /* una orden fallida no debe detener la cola */ }
            }, TaskScheduler.Default);
        }
    }

    public void Cerrar()
    {
        Task pendiente;
        lock (candado)
        {
            cerrada = true;
            pendiente = ultima;
        }
        try { pendiente.Wait(1500); } catch { /* se sale igualmente */ }
    }
}
