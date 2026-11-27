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
    private readonly Panel lienzo;
    private Color colorAplicado = Colors.Black;

    public bool EnProyector { get; }

    public VentanaSalida(Motor motor, Screen? proyector)
    {
        this.motor = motor;
        EnProyector = proyector != null;
        Title = "Salida de Proyectapp";
        Background = Brushes.Black;

        video = new VideoView { MediaPlayer = motor.Reproductor };
        imagen = new Image { Stretch = Stretch.Uniform, IsVisible = false };
        lienzo = new Panel { Background = Brushes.Black };
        lienzo.Children.Add(video);
        lienzo.Children.Add(imagen);
        Content = lienzo;

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
    }

    /// El vídeo es una superficie nativa que tapa lo demás: para mostrar negro o una imagen se aparta.
    private void Aplicar()
    {
        var verVideo = motor.EsVideo && !motor.Negro;
        var fija = !motor.EsVideo && !motor.Negro ? motor.ImagenVisible : null;
        if (!ReferenceEquals(imagen.Source, fija)) imagen.Source = fija;
        if (imagen.IsVisible != (fija != null)) imagen.IsVisible = fija != null;

        // El color elegido solo se ve en el fondo entre vídeos; NEGRO es siempre negro.
        var color = motor.Contenido == Contenido.Fondo && !motor.Negro ? motor.ColorDeFondo : Colors.Black;
        if (color != colorAplicado)
        {
            colorAplicado = color;
            var pincel = new SolidColorBrush(color);
            lienzo.Background = pincel;
            Background = pincel;
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
}
