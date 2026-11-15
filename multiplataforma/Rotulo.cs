using System.Globalization;
using Avalonia;
using Avalonia.Media;
using Avalonia.Media.Imaging;

namespace Proyectapp;

/// Dibuja un mensaje centrado, en claro sobre negro, a tamaño de proyección.
public static class Rotulo
{
    public static Bitmap Imagen(string texto, bool cifrasFijas = false)
    {
        const int ancho = 1920, alto = 1080;
        var lienzo = new RenderTargetBitmap(new PixelSize(ancho, alto), new Vector(96, 96));
        using var dibujo = lienzo.CreateDrawingContext();
        dibujo.FillRectangle(Brushes.Black, new Rect(0, 0, ancho, alto));

        var familia = cifrasFijas ? Paleta.Mono : FontFamily.Default;
        var letra = new Typeface(familia, FontStyle.Normal, FontWeight.Bold);
        var color = new SolidColorBrush(Color.Parse("#F1EDDF"));
        const double cajaAncho = 1580, cajaAlto = 820;
        double punto = 170;
        FormattedText formato;
        while (true)
        {
            formato = new FormattedText(texto, CultureInfo.CurrentCulture, FlowDirection.LeftToRight, letra, punto, color)
            {
                MaxTextWidth = cajaAncho,
                TextAlignment = TextAlignment.Center,
            };
            if (formato.Height <= cajaAlto || punto <= 40) break;
            punto -= 10;
        }
        dibujo.DrawText(formato, new Point((ancho - cajaAncho) / 2, (alto - formato.Height) / 2));
        return lienzo;
    }
}
