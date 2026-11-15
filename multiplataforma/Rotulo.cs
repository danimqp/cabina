using System.Globalization;
using Avalonia;
using Avalonia.Media;
using Avalonia.Media.Imaging;

namespace Proyectapp;

/// Dibuja un mensaje centrado, en claro sobre negro, a tamaño de proyección.
public static class Rotulo
{
    /// `escala` menor que 1 dibuja el mismo rótulo en pequeño (para miniaturas), sin pasar por una copia reducida.
    public static Bitmap Imagen(string texto, bool cifrasFijas = false, double escala = 1)
    {
        var ancho = Math.Max(16, (int)Math.Round(1920 * escala));
        var alto = Math.Max(9, (int)Math.Round(1080 * escala));
        var lienzo = new RenderTargetBitmap(new PixelSize(ancho, alto), new Vector(96, 96));
        using var dibujo = lienzo.CreateDrawingContext();
        dibujo.FillRectangle(Brushes.Black, new Rect(0, 0, ancho, alto));

        var familia = cifrasFijas ? Paleta.Mono : FontFamily.Default;
        var letra = new Typeface(familia, FontStyle.Normal, FontWeight.Bold);
        var color = new SolidColorBrush(Color.Parse("#F1EDDF"));
        double cajaAncho = 1580 * escala, cajaAlto = 820 * escala;
        var punto = 170 * escala;
        var minimo = 40 * escala;
        var paso = 10 * escala;
        FormattedText formato;
        while (true)
        {
            formato = new FormattedText(texto, CultureInfo.CurrentCulture, FlowDirection.LeftToRight, letra, punto, color)
            {
                MaxTextWidth = cajaAncho,
                TextAlignment = TextAlignment.Center,
            };
            if (formato.Height <= cajaAlto || punto <= minimo) break;
            punto -= paso;
        }
        dibujo.DrawText(formato, new Point((ancho - cajaAncho) / 2, (alto - formato.Height) / 2));
        return lienzo;
    }
}
