using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;

namespace Cabina;

public class App : Application
{
    public override void Initialize()
    {
        Styles.Add(new FluentTheme());
        RequestedThemeVariant = ThemeVariant.Dark;
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime escritorio)
        {
            var motor = new Motor();
            var ventana = new VentanaControl(motor);
            escritorio.MainWindow = ventana;
            escritorio.ShutdownMode = ShutdownMode.OnMainWindowClose;
            escritorio.Exit += (_, _) => motor.Dispose();
            Pruebas.ArrancarSiProcede(motor, ventana, escritorio.Args ?? Array.Empty<string>());
        }
        base.OnFrameworkInitializationCompleted();
    }
}
