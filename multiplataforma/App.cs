using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;

namespace Proyectapp;

public class App : Application
{
    public override void Initialize()
    {
        Name = "Proyectapp";
        Styles.Add(new FluentTheme());
        RequestedThemeVariant = ThemeVariant.Dark;
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime escritorio)
        {
            var argumentos = escritorio.Args ?? Array.Empty<string>();
            var motor = new Motor(persistir: !Pruebas.Activa(argumentos));
            var ventana = new VentanaControl(motor);
            escritorio.MainWindow = ventana;
            if (!Pruebas.Activa(argumentos)) ventana.Opened += (_, _) => ventana.AyudaInicial();
            escritorio.ShutdownMode = ShutdownMode.OnMainWindowClose;
            escritorio.Exit += (_, _) => motor.Dispose();
            Pruebas.ArrancarSiProcede(motor, ventana, argumentos);
        }
        base.OnFrameworkInitializationCompleted();
    }
}
