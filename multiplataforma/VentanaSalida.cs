using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Platform;
using LibVLCSharp.Avalonia;

namespace Cabina;

/// La ventana del público: solo vídeo, imagen o negro. Nunca controles.
public sealed class VentanaSalida : Window
{
    private readonly Motor motor;
    private readonly VideoView video;
    private readonly Image imagen;

    public bool EnProyector { get; }

    public VentanaSalida(Motor motor, Screen? proyector)
    {
        this.motor = motor;
        EnProyector = proyector != null;
        Title = "Salida de Cabina";
        Background = Brushes.Black;

        video = new VideoView { MediaPlayer = motor.Reproductor };
        imagen = new Image { Stretch = Stretch.Uniform, IsVisible = false };
        var lienzo = new Panel { Background = Brushes.Black };
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

        motor.Cambio += Aplicar;
        Closed += (_, _) => motor.Cambio -= Aplicar;
        Opened += (_, _) => Aplicar();
    }

    /// El vídeo es una superficie nativa que tapa lo demás: para mostrar negro o una imagen se aparta.
    private void Aplicar()
    {
        var verVideo = motor.EsVideo && !motor.Negro;
        var verImagen = motor.EsImagen && !motor.Negro && motor.ImagenVisible != null;
        if (imagen.Source != (verImagen ? motor.ImagenVisible : null))
        {
            imagen.Source = verImagen ? motor.ImagenVisible : null;
        }
        if (imagen.IsVisible != verImagen) imagen.IsVisible = verImagen;
        // No se usa IsVisible: la superficie debe existir siempre para que VLC no abra una ventana propia.
        // Fuera de vídeo se reduce a un punto negro en una esquina.
        if (verVideo)
        {
            video.Width = double.NaN;
            video.Height = double.NaN;
            video.HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch;
            video.VerticalAlignment = Avalonia.Layout.VerticalAlignment.Stretch;
        }
        else
        {
            video.Width = 1;
            video.Height = 1;
            video.HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Left;
            video.VerticalAlignment = Avalonia.Layout.VerticalAlignment.Top;
        }
    }
}
