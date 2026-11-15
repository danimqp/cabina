using Avalonia.Media;

namespace Proyectapp;

/// Colores de Proyectapp, tomados de su logo: verde oscuro, lima y crema.
public static class Paleta
{
    public static readonly IBrush Tinta = Pincel("#0B1613");
    public static readonly IBrush Pizarra = Pincel("#10201B");
    public static readonly IBrush Panel = Pincel("#1B3029");
    public static readonly IBrush Papel = Pincel("#F1EDDF");
    public static readonly IBrush Tenue = Pincel("#99F1EDDF");
    /// Acento: lo que está en pantalla y las acciones principales.
    public static readonly IBrush Lima = Pincel("#D2D25A");
    public static readonly IBrush LimaSuave = Pincel("#33D2D25A");
    /// Solo para avisos que piden atención.
    public static readonly IBrush Ambar = Pincel("#F0A333");
    /// Solo para errores graves.
    public static readonly IBrush Rojo = Pincel("#E0685A");

    public static readonly FontFamily Mono = new("Consolas, Menlo, Courier New, monospace");

    private static IBrush Pincel(string hex) => new SolidColorBrush(Color.Parse(hex));
}
