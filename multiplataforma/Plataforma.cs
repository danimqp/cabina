using System.Diagnostics;
using System.Runtime.InteropServices;
using Avalonia.Controls;
using LibVLCSharp.Shared;

namespace Proyectapp;

/// Lo que cada sistema hace a su manera: cargar VLC, impedir el reposo y los atajos globales.
public static class Plataforma
{
    public static bool EsWindows => RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
    public static bool EsMac => RuntimeInformation.IsOSPlatform(OSPlatform.OSX);

    [DllImport("libc", EntryPoint = "setenv")]
    private static extern int FijarEntorno(string nombre, string valor, int sobrescribir);

    /// Carga el motor VLC que viaja dentro de la app.
    public static void CargarVlc()
    {
        if (EsMac)
        {
            var raiz = Path.Combine(AppContext.BaseDirectory, "vlc");
            var bibliotecas = Path.Combine(raiz, "lib");
            if (Directory.Exists(bibliotecas))
            {
                FijarEntorno("VLC_PLUGIN_PATH", Path.Combine(raiz, "plugins"), 1);
                Core.Initialize(bibliotecas);
                return;
            }
        }
        Core.Initialize();
    }

    // ----- Impedir el reposo mientras la salida está abierta -----

    [DllImport("kernel32.dll")]
    private static extern uint SetThreadExecutionState(uint estado);

    private static Process? cafeina;

    public static void ImpedirReposo(bool impedir)
    {
        try
        {
            if (EsWindows)
            {
                const uint continuo = 0x80000000, sistema = 0x00000001, pantalla = 0x00000002;
                SetThreadExecutionState(impedir ? continuo | sistema | pantalla : continuo);
            }
            else if (EsMac)
            {
                if (impedir && cafeina == null)
                {
                    cafeina = Process.Start(new ProcessStartInfo("/usr/bin/caffeinate", $"-d -i -w {Environment.ProcessId}")
                    {
                        UseShellExecute = false,
                        CreateNoWindow = true,
                    });
                }
                else if (!impedir && cafeina != null)
                {
                    if (!cafeina.HasExited) cafeina.Kill();
                    cafeina.Dispose();
                    cafeina = null;
                }
            }
        }
        catch
        {
            // Si no se puede, la proyección sigue; solo puede atenuarse la pantalla.
        }
    }

    // ----- Atajos globales (Windows): Ctrl+Alt+B negro, Ctrl+Alt+P pausa -----

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr ventana, int id, uint modificadores, uint tecla);

    public static int AtajosRegistrados { get; private set; }
    public static bool HayAtajosGlobales => EsWindows;

    public static void InstalarAtajosGlobales(Window ventana, Action negro, Action pausa)
    {
        if (!EsWindows) return;
        try
        {
            var manejador = ventana.TryGetPlatformHandle()?.Handle ?? IntPtr.Zero;
            if (manejador == IntPtr.Zero) return;
            const uint alt = 0x0001, control = 0x0002, sinRepetir = 0x4000;
            if (RegisterHotKey(manejador, 1, alt | control | sinRepetir, 0x42)) AtajosRegistrados++;
            if (RegisterHotKey(manejador, 2, alt | control | sinRepetir, 0x50)) AtajosRegistrados++;
            Win32Properties.AddWndProcHookCallback(ventana, (IntPtr hwnd, uint mensaje, IntPtr w, IntPtr l, ref bool atendido) =>
            {
                if (mensaje == 0x0312)
                {
                    if (w.ToInt32() == 1) negro();
                    else if (w.ToInt32() == 2) pausa();
                    atendido = true;
                }
                return IntPtr.Zero;
            });
        }
        catch
        {
            // Sin atajos globales la app funciona igual.
        }
    }
}
