using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform;
using LibVLCSharp.Avalonia;

namespace Proyectapp;

/// La ventana del público: solo vídeo, imagen o negro. Nunca controles.
public sealed class VentanaSalida : Window
{
    private readonly Motor motor;
    private readonly VideoView video;
    private readonly Image imagen;
    private readonly Panel area;
    private readonly Panel marcoImagen;
    private readonly PatronDePrueba patron = new() { IsVisible = false };
    private Color colorAplicado = Colors.Black;

    public bool EnProyector { get; }

    public VentanaSalida(Motor motor, Screen? proyector)
    {
        this.motor = motor;
        EnProyector = proyector != null;
        Title = "Salida de Proyectapp";
        Background = Brushes.Black;

        video = new VideoView { MediaPlayer = motor.Reproductor };
        imagen = new Image { Stretch = Stretch.Fill, IsVisible = false, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        // La imagen va en su propio marco recortado: con zoom o «Llenar» no se sale de la zona de proyección.
        marcoImagen = new Panel { ClipToBounds = true };
        marcoImagen.Children.Add(imagen);
        // La zona de proyección: la pantalla menos los márgenes de la sala. Fuera de ella, siempre negro.
        area = new Panel { Background = Brushes.Black, ClipToBounds = true };
        area.Children.Add(video);
        area.Children.Add(marcoImagen);
        area.Children.Add(patron);
        var pantalla = new Panel { Background = Brushes.Black };
        pantalla.Children.Add(area);
        Content = pantalla;

        if (proyector != null)
        {
            SystemDecorations = SystemDecorations.None;
            ShowInTaskbar = false;
            CanResize = false;
            Topmost = true;
            Cursor = new Cursor(StandardCursorType.None);
            WindowStartupLocation = WindowStartupLocation.Manual;
            Position = proyector.Bounds.Position;
            Width = proyector.Bounds.Width / proyector.Scaling;
            Height = proyector.Bounds.Height / proyector.Scaling;
            Opened += (_, _) => WindowState = WindowState.FullScreen;
        }
        else
        {
            Width = 960;
            Height = 540;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
        }
        ShowActivated = false;

        motor.Cambio += Aplicar;
        Closed += (_, _) => motor.Cambio -= Aplicar;
        Opened += (_, _) => Aplicar();
        pantalla.SizeChanged += (_, _) => Aplicar();
        area.SizeChanged += (_, _) =>
        {
            motor.FijarAreaSalida(area.Bounds.Size);
            ColocarImagen();
        };
    }

    /// El vídeo es una superficie nativa que tapa lo demás: para mostrar negro o una imagen se aparta.
    private void Aplicar()
    {
        var ajuste = motor.Funcion.Ajuste;
        var ventana = (Content as Control)?.Bounds.Size ?? Bounds.Size;
        var margen = new Thickness(
            Math.Round(ventana.Width * ajuste.MargenIzquierda), Math.Round(ventana.Height * ajuste.MargenArriba),
            Math.Round(ventana.Width * ajuste.MargenDerecha), Math.Round(ventana.Height * ajuste.MargenAbajo));
        if (area.Margin != margen) area.Margin = margen;

        var prueba = motor.Prueba && !motor.Negro && !motor.EsVideo;
        if (patron.IsVisible != prueba) patron.IsVisible = prueba;
        var verVideo = motor.EsVideo && !motor.Negro;
        var fija = !motor.EsVideo && !motor.Negro && !prueba ? motor.ImagenVisible : null;
        if (!ReferenceEquals(imagen.Source, fija)) imagen.Source = fija;
        if (imagen.IsVisible != (fija != null)) imagen.IsVisible = fija != null;
        ColocarImagen();

        // El color elegido solo se ve en el fondo entre vídeos; NEGRO es siempre negro.
        var color = motor.Contenido == Contenido.Fondo && !motor.Negro && !prueba ? motor.ColorDeFondo : Colors.Black;
        if (color != colorAplicado)
        {
            colorAplicado = color;
            area.Background = new SolidColorBrush(color);
        }

        // No se usa IsVisible: la superficie debe existir siempre para que VLC no abra una ventana propia.
        // Fuera de vídeo se reduce a un punto negro en una esquina.
        if (verVideo)
        {
            if (!double.IsNaN(video.Width))
            {
                video.Width = double.NaN;
                video.Height = double.NaN;
                video.HorizontalAlignment = HorizontalAlignment.Stretch;
                video.VerticalAlignment = VerticalAlignment.Stretch;
            }
        }
        else if (double.IsNaN(video.Width))
        {
            video.Width = 1;
            video.Height = 1;
            video.HorizontalAlignment = HorizontalAlignment.Left;
            video.VerticalAlignment = VerticalAlignment.Top;
        }
    }

    /// Tamaño y posición de la imagen fija según el encuadre, el zoom y la posición elegidos.
    /// El fondo y los mensajes van siempre enteros; las imágenes de la lista siguen el ajuste.
    private void ColocarImagen()
    {
        if (imagen.Source is not Avalonia.Media.Imaging.Bitmap mapa) return;
        var zona = area.Bounds.Size;
        if (zona.Width <= 0 || zona.Height <= 0) return;
        var dePieza = motor.EsImagen && !motor.EsMensaje && motor.EnPantalla != null;
        var encuadre = dePieza ? motor.EncuadreDe(motor.EnPantalla!) : Encuadre.Completa;
        var zoom = dePieza ? motor.Funcion.Ajuste.Zoom : 1;
        var tamano = Encuadres.TamanoImagen(mapa.Size, zona, encuadre == Encuadre.Llenar ? Encuadre.Llenar : Encuadre.Completa, zoom);
        if (Math.Abs(imagen.Width - tamano.Width) > 0.5) imagen.Width = tamano.Width;
        if (Math.Abs(imagen.Height - tamano.Height) > 0.5) imagen.Height = tamano.Height;
        // Mover: X positivo enseña la parte derecha, así que la imagen se desplaza a la izquierda.
        var sobraX = Math.Max(0, tamano.Width - zona.Width) / 2;
        var sobraY = Math.Max(0, tamano.Height - zona.Height) / 2;
        var dx = dePieza ? -motor.Funcion.Ajuste.X * sobraX : 0;
        var dy = dePieza ? -motor.Funcion.Ajuste.Y * sobraY : 0;
        if (imagen.RenderTransform is not TranslateTransform t || Math.Abs(t.X - dx) > 0.5 || Math.Abs(t.Y - dy) > 0.5)
        {
            imagen.RenderTransform = new TranslateTransform(dx, dy);
        }
    }
}

/// Imagen de prueba para ajustar el proyector: bordes, cuadrícula, centro y tamaño en píxeles.
public sealed class PatronDePrueba : Control
{
    public override void Render(DrawingContext dibujo)
    {
        var w = Bounds.Width;
        var h = Bounds.Height;
        if (w <= 0 || h <= 0) return;
        var escala = TopLevel.GetTopLevel(this)?.RenderScaling ?? 1;
        dibujo.FillRectangle(Brushes.Black, new Rect(0, 0, w, h));

        var tenue = new Pen(new SolidColorBrush(Color.Parse("#555555")), 1);
        for (var i = 1; i < 8; i++)
        {
            dibujo.DrawLine(tenue, new Point(w * i / 8, 0), new Point(w * i / 8, h));
            dibujo.DrawLine(tenue, new Point(0, h * i / 8), new Point(w, h * i / 8));
        }

        var lima = new SolidColorBrush(Color.Parse("#D2D25A"));
        var claro = new SolidColorBrush(Color.Parse("#F1EDDF"));
        var borde = Math.Max(4, Math.Min(w, h) / 120);
        dibujo.DrawRectangle(null, new Pen(lima, borde), new Rect(borde / 2, borde / 2, w - borde, h - borde));

        // Esquinas: flechas que deben verse enteras
        var lado = Math.Min(w, h) / 9;
        foreach (var (x, y, sx, sy) in new[] { (0.0, 0.0, 1.0, 1.0), (w, 0.0, -1.0, 1.0), (0.0, h, 1.0, -1.0), (w, h, -1.0, -1.0) })
        {
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                c.BeginFigure(new Point(x + sx * borde, y + sy * borde), true);
                c.LineTo(new Point(x + sx * (borde + lado), y + sy * borde));
                c.LineTo(new Point(x + sx * borde, y + sy * (borde + lado)));
                c.EndFigure(true);
            }
            dibujo.DrawGeometry(claro, null, g);
        }

        // Centro: cruz y círculo (si el círculo sale ovalado, la imagen está deformada)
        var centro = new Point(w / 2, h / 2);
        var radio = Math.Min(w, h) * 0.3;
        var linea = new Pen(claro, Math.Max(2, borde / 2));
        dibujo.DrawEllipse(null, linea, centro, radio, radio);
        dibujo.DrawLine(linea, new Point(centro.X - radio * 0.25, centro.Y), new Point(centro.X + radio * 0.25, centro.Y));
        dibujo.DrawLine(linea, new Point(centro.X, centro.Y - radio * 0.25), new Point(centro.X, centro.Y + radio * 0.25));

        // Escala de grises para el brillo y el contraste
        var franja = new Rect(w * 0.2, h * 0.84, w * 0.6, h * 0.06);
        for (var i = 0; i < 10; i++)
        {
            var v = (byte)Math.Round(255.0 * i / 9);
            dibujo.FillRectangle(new SolidColorBrush(Color.FromRgb(v, v, v)),
                new Rect(franja.X + franja.Width * i / 10, franja.Y, franja.Width / 10 + 0.5, franja.Height));
        }

        var letra = new Typeface(Paleta.Mono, FontStyle.Normal, FontWeight.Bold);
        void Texto(string texto, double y, double tamano, IBrush color)
        {
            var f = new FormattedText(texto, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight, letra, tamano, color);
            dibujo.DrawText(f, new Point((w - f.Width) / 2, y));
        }
        var punto = Math.Max(12, h / 22);
        Texto("PROYECTAPP · IMAGEN DE PRUEBA", h * 0.1, punto, lima);
        Texto($"{Math.Round(w * escala)} × {Math.Round(h * escala)} píxeles", h * 0.1 + punto * 1.6, punto * 0.8, claro);
        Texto("Los cuatro bordes y las esquinas deben verse enteros. El círculo debe ser redondo.", h * 0.75, punto * 0.6, claro);
    }
}
