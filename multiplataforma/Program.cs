using Avalonia;

namespace Proyectapp;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        // Una sola copia abierta: dos a la vez escribirían la misma función guardada.
        using var unica = new Mutex(true, "org.muyuna.proyectapp", out var soyLaPrimera);
        if (!soyLaPrimera && !args.Contains("--autoprueba")) return;
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace();
}
