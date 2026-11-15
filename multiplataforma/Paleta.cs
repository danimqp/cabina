using Avalonia.Media;

namespace Cabina;

/// Colores de Cabina, los mismos que en la versión de Mac.
public static class Paleta
{
    public static readonly IBrush Tinta = Pincel("#0E1417");
    public static readonly IBrush Pizarra = Pincel("#171F22");
    public static readonly IBrush Panel = Pincel("#20272B");
    public static readonly IBrush Papel = Pincel("#E6E3D6");
    public static readonly IBrush Tenue = Pincel("#8CE6E3D6");
    public static readonly IBrush Ambar = Pincel("#F0A333");
    public static readonly IBrush AmbarSuave = Pincel("#38F0A333");
    public static readonly IBrush Verde = Pincel("#5EBF8F");
    public static readonly IBrush Rojo = Pincel("#D95B4E");

    public static readonly FontFamily Mono = new("Consolas, Menlo, Courier New, monospace");

    private static IBrush Pincel(string hex) => new SolidColorBrush(Color.Parse(hex));
}
