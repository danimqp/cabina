using System.Globalization;
using Avalonia;
using Avalonia.Media.Imaging;

namespace Proyectapp;

/// Cómo se coloca cada pieza en la pantalla del público.
public enum Encuadre
{
    /// Se ve la imagen entera; si su forma no coincide con la pantalla, quedan bandas.
    Completa,
    /// Amplía hasta que no quede negro; recorta un poco los bordes.
    Llenar,
    /// Recorta las bandas negras que trae el propio archivo y encaja el resto.
    SinBandas,
}

/// Bandas negras que trae un vídeo dentro del archivo, en fracción de su alto o ancho.
public sealed class Bandas
{
    public double Arriba { get; set; }
    public double Abajo { get; set; }
    public double Izquierda { get; set; }
    public double Derecha { get; set; }

    public bool Hay => Arriba + Abajo + Izquierda + Derecha > 0;

    public Bandas Saneadas()
    {
        static double A(double v) => double.IsFinite(v) ? Math.Clamp(v, 0, 0.4) : 0;
        Arriba = A(Arriba);
        Abajo = A(Abajo);
        Izquierda = A(Izquierda);
        Derecha = A(Derecha);
        return this;
    }

    public string Texto =>
        !Hay ? "no tiene" : (Arriba + Abajo > 0 ? $"arriba {Math.Round(Arriba * 100)} % y abajo {Math.Round(Abajo * 100)} %" : "")
            + (Arriba + Abajo > 0 && Izquierda + Derecha > 0 ? " · " : "")
            + (Izquierda + Derecha > 0 ? $"izquierda {Math.Round(Izquierda * 100)} % y derecha {Math.Round(Derecha * 100)} %" : "");
}

/// Ajuste de la sala: tamaño, posición y márgenes de lo que se proyecta.
public sealed class Ajuste
{
    /// 1 = tamaño normal; hasta 3.
    public double Zoom { get; set; } = 1;
    /// De -1 a 1: qué parte se ve cuando la imagen es más grande que la pantalla.
    public double X { get; set; }
    public double Y { get; set; }
    /// Márgenes de la pantalla, en fracción de su ancho o alto (hasta 0,3).
    public double MargenArriba { get; set; }
    public double MargenAbajo { get; set; }
    public double MargenIzquierda { get; set; }
    public double MargenDerecha { get; set; }

    public bool HayMargenes => MargenArriba + MargenAbajo + MargenIzquierda + MargenDerecha > 0;

    public Ajuste Saneado()
    {
        static double R(double v, double min, double max, double defecto) => double.IsFinite(v) ? Math.Clamp(v, min, max) : defecto;
        Zoom = R(Zoom, 1, 3, 1);
        X = R(X, -1, 1, 0);
        Y = R(Y, -1, 1, 0);
        MargenArriba = R(MargenArriba, 0, 0.3, 0);
        MargenAbajo = R(MargenAbajo, 0, 0.3, 0);
        MargenIzquierda = R(MargenIzquierda, 0, 0.3, 0);
        MargenDerecha = R(MargenDerecha, 0, 0.3, 0);
        return this;
    }
}

/// Cálculos del encuadre, sin interfaz: qué trozo del vídeo se proyecta y dónde están sus bandas.
public static class Encuadres
{
    public static string Nombre(Encuadre e) => e switch
    {
        Encuadre.Llenar => "Llenar la pantalla",
        Encuadre.SinBandas => "Quitar bandas del archivo",
        _ => "Imagen completa",
    };

    /// Trozo del vídeo (en sus píxeles) que se proyecta, o null si es el vídeo entero.
    /// `ancho`/`alto`: tamaño del vídeo; `aspectoPixel`: forma de sus píxeles (1 casi siempre);
    /// `aspectoSalida`: ancho entre alto de la zona de proyección.
    public static (int Ancho, int Alto, int X, int Y)? Recorte(
        int ancho, int alto, double aspectoPixel, double aspectoSalida, Encuadre encuadre, Bandas? bandas, Ajuste ajuste)
    {
        if (ancho <= 0 || alto <= 0) return null;
        if (!double.IsFinite(aspectoPixel) || aspectoPixel <= 0) aspectoPixel = 1;
        var b = encuadre != Encuadre.Completa && bandas != null ? bandas : new Bandas();
        double bx = ancho * b.Izquierda, by = alto * b.Arriba;
        double bw = ancho * (1 - b.Izquierda - b.Derecha), bh = alto * (1 - b.Arriba - b.Abajo);
        if (bw < 16 || bh < 16)
        {
            bx = 0;
            by = 0;
            bw = ancho;
            bh = alto;
        }
        double cw = bw, ch = bh;
        if (encuadre == Encuadre.Llenar && double.IsFinite(aspectoSalida) && aspectoSalida > 0)
        {
            var aspectoBase = bw * aspectoPixel / bh;
            if (aspectoBase > aspectoSalida) cw = bh * aspectoSalida / aspectoPixel;
            else ch = bw * aspectoPixel / aspectoSalida;
        }
        var zoom = Math.Clamp(ajuste.Zoom, 1, 3);
        cw /= zoom;
        ch /= zoom;
        var cx = bx + (bw - cw) / 2 * (1 + Math.Clamp(ajuste.X, -1, 1));
        var cy = by + (bh - ch) / 2 * (1 + Math.Clamp(ajuste.Y, -1, 1));
        int w = (int)Math.Round(cw), h = (int)Math.Round(ch), x = (int)Math.Round(cx), y = (int)Math.Round(cy);
        w = Math.Clamp(w, 16, ancho);
        h = Math.Clamp(h, 16, alto);
        x = Math.Clamp(x, 0, ancho - w);
        y = Math.Clamp(y, 0, alto - h);
        if (w >= ancho - 1 && h >= alto - 1) return null;
        return (w, h, x, y);
    }

    /// Texto que entiende VLC para recortar, como píxeles quitados de cada borde: "IZQUIERDA+ARRIBA+DERECHA+ABAJO".
    /// No se usa la forma "ANCHOxALTO+X+Y": VLC 3 la lee mal (toma ancho y alto como bordes derecho e inferior).
    public static string? Geometria((int Ancho, int Alto, int X, int Y)? recorte, int ancho, int alto) =>
        recorte is { } r
            ? string.Create(CultureInfo.InvariantCulture, $"{r.X}+{r.Y}+{Math.Max(0, ancho - r.X - r.Ancho)}+{Math.Max(0, alto - r.Y - r.Alto)}")
            : null;

    /// Tamaño (en unidades de pantalla) de una imagen fija colocada en una zona, con su zoom.
    public static Size TamanoImagen(Size imagen, Size zona, Encuadre encuadre, double zoom)
    {
        if (imagen.Width <= 0 || imagen.Height <= 0 || zona.Width <= 0 || zona.Height <= 0) return zona;
        var fx = zona.Width / imagen.Width;
        var fy = zona.Height / imagen.Height;
        var f = (encuadre == Encuadre.Llenar ? Math.Max(fx, fy) : Math.Min(fx, fy)) * Math.Clamp(zoom, 1, 3);
        return new Size(imagen.Width * f, imagen.Height * f);
    }

    /// Detecta las bandas negras que comparten varios fotogramas del mismo vídeo.
    /// Los fotogramas casi negros (fundidos, créditos) se descartan. Hacen falta al menos tres válidos.
    public static Bandas? DetectarBandas(IEnumerable<Bitmap> fotogramas)
    {
        var medidas = new List<(double Arriba, double Abajo, double Izquierda, double Derecha)>();
        foreach (var fotograma in fotogramas)
        {
            var m = Medir(fotograma);
            if (m != null) medidas.Add(m.Value);
        }
        if (medidas.Count < 3) return null;
        // Una banda solo cuenta si está en todos: se toma la más estrecha.
        static double Limpia(double v) => v < 0.012 ? 0 : Math.Min(v, 0.4);
        return new Bandas
        {
            Arriba = Limpia(medidas.Min(m => m.Arriba)),
            Abajo = Limpia(medidas.Min(m => m.Abajo)),
            Izquierda = Limpia(medidas.Min(m => m.Izquierda)),
            Derecha = Limpia(medidas.Min(m => m.Derecha)),
        };
    }

    private const int Umbral = 30;

    private static (double, double, double, double)? Medir(Bitmap fotograma)
    {
        try
        {
            var w = fotograma.PixelSize.Width;
            var h = fotograma.PixelSize.Height;
            if (w < 16 || h < 16) return null;
            var datos = Pixeles(fotograma);
            if (datos == null) return null;
            bool FilaOscura(int y)
            {
                var claros = 0;
                for (var x = 0; x < w; x++) if (Brillo(datos, (y * w + x) * 4) > Umbral) claros++;
                return claros <= w / 50;
            }
            bool ColumnaOscura(int x)
            {
                var claros = 0;
                for (var y = 0; y < h; y++) if (Brillo(datos, (y * w + x) * 4) > Umbral) claros++;
                return claros <= h / 50;
            }
            int arriba = 0, abajo = 0, izquierda = 0, derecha = 0;
            while (arriba < h && FilaOscura(arriba)) arriba++;
            // Un fotograma casi negro no dice nada de las bandas.
            if (arriba >= h * 0.45) return null;
            while (abajo < h - arriba && FilaOscura(h - 1 - abajo)) abajo++;
            while (izquierda < w && ColumnaOscura(izquierda)) izquierda++;
            if (izquierda >= w * 0.45) return null;
            while (derecha < w - izquierda && ColumnaOscura(w - 1 - derecha)) derecha++;
            return ((double)arriba / h, (double)abajo / h, (double)izquierda / w, (double)derecha / w);
        }
        catch
        {
            return null;
        }
    }

    private static int Brillo(byte[] datos, int i) => Math.Max(datos[i], Math.Max(datos[i + 1], datos[i + 2]));

    /// Píxeles en 32 bits por punto (azul, verde, rojo y alfa), pasando por un lienzo propio
    /// para no depender del formato con que se abrió la imagen.
    private static byte[]? Pixeles(Bitmap fotograma)
    {
        var w = fotograma.PixelSize.Width;
        var h = fotograma.PixelSize.Height;
        using var lienzo = new RenderTargetBitmap(new PixelSize(w, h), new Vector(96, 96));
        using (var dibujo = lienzo.CreateDrawingContext())
        {
            dibujo.DrawImage(fotograma, new Rect(0, 0, w, h));
        }
        var bytes = new byte[w * h * 4];
        var asa = System.Runtime.InteropServices.GCHandle.Alloc(bytes, System.Runtime.InteropServices.GCHandleType.Pinned);
        try
        {
            lienzo.CopyPixels(new PixelRect(0, 0, w, h), asa.AddrOfPinnedObject(), bytes.Length, w * 4);
        }
        finally
        {
            asa.Free();
        }
        return bytes;
    }
}
