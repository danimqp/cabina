using System.Text.Json;
using System.Text.Json.Serialization;

namespace Proyectapp;

public enum TipoPieza { Video, Imagen, Texto }

/// Un elemento de la lista: un vídeo, una imagen o un mensaje de texto.
public sealed class Pieza
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Nombre { get; set; } = "";
    public string Ruta { get; set; } = "";
    public TipoPieza Tipo { get; set; }
    public double? Duracion { get; set; }
    /// Contenido de un mensaje de texto.
    public string? Texto { get; set; }
    /// Punto donde se cortó el vídeo la última vez, para poder seguir desde ahí.
    public double? Posicion { get; set; }
    /// Volumen propio de la pieza; si no tiene, usa el general.
    public double? Volumen { get; set; }
    /// Archivo .srt de subtítulos.
    public string? Subtitulos { get; set; }
    /// Recorte: segundo en el que empieza y en el que termina la proyección.
    public double? Inicio { get; set; }
    public double? Fin { get; set; }
    /// Al terminar, lanza sola la pieza siguiente.
    public bool? Encadena { get; set; }

    [JsonIgnore] public bool Pasada { get; set; }

    public static Pieza Mensaje(string texto)
    {
        var titulo = texto.Split('\n', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Trim() ?? texto;
        return new Pieza { Nombre = titulo, Ruta = "", Tipo = TipoPieza.Texto, Texto = texto };
    }
}

/// La programación completa: lista ordenada de piezas y los ajustes de la sala.
/// El archivo guardado usa las mismas claves que la versión anterior de Mac (Cabina).
public sealed class Funcion
{
    public string Nombre { get; set; } = "Función sin título";
    public List<Pieza> Piezas { get; set; } = new();
    public string? RutaFondo { get; set; }
    /// Color del fondo entre vídeos, como "#RRGGBB". Sin valor, negro.
    public string? ColorFondo { get; set; }
    public double Volumen { get; set; } = 1;
    public List<string> Musica { get; set; } = new();
    public double VolumenMusica { get; set; } = 0.6;

    private static readonly JsonSerializerOptions Opciones = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public string AJson() => JsonSerializer.Serialize(this, Opciones);

    public static Funcion DeJson(string json) =>
        (JsonSerializer.Deserialize<Funcion>(json, Opciones) ?? new Funcion()).Saneada();

    /// Acota los valores, para abrir sin riesgo un archivo dañado o ajeno.
    public Funcion Saneada()
    {
        static double? Tiempo(double? v) => v is { } x && double.IsFinite(x) && x >= 0 && x < 1_000_000 ? x : null;
        static double Unidad(double v) => double.IsFinite(v) ? Math.Clamp(v, 0, 1) : 1;
        static string Corto(string? s, int n) => s == null ? "" : s.Length > n ? s[..n] : s;

        Nombre = Corto(Nombre, 200);
        Volumen = Unidad(Volumen);
        ColorFondo = Formatos.ColorValido(ColorFondo);
        VolumenMusica = Unidad(VolumenMusica);
        Musica = (Musica ?? new()).Where(r => !string.IsNullOrWhiteSpace(r)).Take(500).ToList();
        var vistos = new HashSet<Guid>();
        Piezas = (Piezas ?? new()).Where(p => p != null).Take(2000).ToList();
        foreach (var p in Piezas)
        {
            if (p.Id == Guid.Empty || !vistos.Add(p.Id))
            {
                p.Id = Guid.NewGuid();
                vistos.Add(p.Id);
            }
            p.Nombre = Corto(p.Nombre, 300);
            p.Ruta = p.Ruta ?? "";
            p.Texto = p.Texto == null ? null : Corto(p.Texto, 2000);
            p.Duracion = Tiempo(p.Duracion);
            p.Posicion = Tiempo(p.Posicion);
            p.Inicio = Tiempo(p.Inicio);
            p.Fin = Tiempo(p.Fin);
            if (p.Inicio is { } a && p.Fin is { } b && b <= a + 1) p.Fin = null;
            if (p.Volumen is { } v) p.Volumen = Unidad(v);
            if (p.Tipo == TipoPieza.Texto)
            {
                p.Ruta = "";
                p.Subtitulos = null;
            }
        }
        return this;
    }
}

public static class Formatos
{
    public static readonly string[] Video =
    {
        "mp4", "mov", "m4v", "mkv", "avi", "wmv", "mpg", "mpeg", "webm", "flv", "ts", "m2ts", "mts", "3gp", "ogv", "vob", "divx",
    };

    public static readonly string[] Imagen = { "jpg", "jpeg", "png", "bmp", "webp" };
    public static readonly string[] Audio = { "mp3", "m4a", "aac", "wav", "aiff", "aif", "ogg", "flac", "wma" };

    /// "#1f4e79", "1F4E79" → "#1F4E79". Cualquier otra cosa → null (negro).
    public static string? ColorValido(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        var limpio = texto.Trim().TrimStart('#').ToUpperInvariant();
        if (limpio.Length != 6 || !limpio.All(Uri.IsHexDigit)) return null;
        return limpio == "000000" ? null : "#" + limpio;
    }

    public static string Extension(string ruta) => Path.GetExtension(ruta).TrimStart('.').ToLowerInvariant();

    public static TipoPieza? TipoDeArchivo(string ruta)
    {
        var ext = Extension(ruta);
        if (Video.Contains(ext)) return TipoPieza.Video;
        if (Imagen.Contains(ext)) return TipoPieza.Imagen;
        return null;
    }

    /// 75 → "01:15"; 3725 → "1:02:05".
    public static string Tiempo(double segundos)
    {
        if (!double.IsFinite(segundos) || segundos <= 0 || segundos > 1e9) return "00:00";
        var total = (long)Math.Floor(segundos);
        var h = total / 3600;
        var m = total % 3600 / 60;
        var s = total % 60;
        return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m:00}:{s:00}";
    }

    /// `true` si la ruta lleva a un archivo normal y, si se indica, no supera el tamaño.
    public static bool EsArchivoNormal(string? ruta, long? maximo = null)
    {
        if (string.IsNullOrEmpty(ruta)) return false;
        try
        {
            var info = new FileInfo(ruta);
            if (!info.Exists) return false;
            if (info.Attributes.HasFlag(FileAttributes.Directory) || info.Attributes.HasFlag(FileAttributes.Device)) return false;
            return maximo == null || info.Length <= maximo;
        }
        catch
        {
            return false;
        }
    }
}
