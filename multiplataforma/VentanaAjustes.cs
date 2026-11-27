using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;

namespace Proyectapp;

/// Ajustar lo que ve el público: pantalla de salida, encuadre, tamaño, posición, márgenes e imagen de prueba.
/// Los cambios se ven en el proyector al momento y se guardan con la función.
public sealed class VentanaAjustes : Window
{
    private readonly Motor motor;
    private readonly VentanaControl control;
    private bool actualizando;

    private readonly ComboBox pantallas = new() { HorizontalAlignment = HorizontalAlignment.Stretch, FontSize = 13 };
    private readonly TextBlock notaPantalla = Nota();
    private readonly Dictionary<Encuadre, Button> botonesEncuadre = new();
    private readonly TextBlock notaEncuadre = Nota();
    private readonly Button botonPrueba = new();
    private readonly List<(Slider Barra, TextBlock Valor, Func<Ajuste, double> Leer, Func<double, string> Texto)> barras = new();

    public VentanaAjustes(Motor motor, VentanaControl control)
    {
        this.motor = motor;
        this.control = control;
        Title = "Ajustar proyección";
        Width = 540;
        Height = 760;
        MinHeight = 400;
        ShowInTaskbar = false;
        Background = Paleta.Pizarra;
        Foreground = Paleta.Papel;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var panel = new StackPanel { Margin = new Thickness(22, 18), Spacing = 14 };
        panel.Children.Add(new TextBlock { Text = "Ajustar proyección", FontSize = 18, FontWeight = FontWeight.Bold });
        panel.Children.Add(Nota("Los cambios se ven en el proyector al momento y se guardan con la función. Úsalo con la imagen de prueba antes de que entre el público."));

        // --- Imagen de prueba ---
        Dialogos.Estilo(botonPrueba, Paleta.Panel, grande: true);
        botonPrueba.HorizontalAlignment = HorizontalAlignment.Stretch;
        botonPrueba.HorizontalContentAlignment = HorizontalAlignment.Center;
        botonPrueba.Click += (_, _) => motor.AlternarPrueba();
        panel.Children.Add(botonPrueba);

        // --- Pantalla de salida ---
        panel.Children.Add(Separador());
        panel.Children.Add(Dialogos.Rotulo("PANTALLA DE SALIDA"));
        pantallas.SelectionChanged += (_, _) =>
        {
            if (actualizando) return;
            var clave = (pantallas.SelectedItem as ComboBoxItem)?.Tag as string;
            var hecho = control.ElegirPantallaDeSalida(string.IsNullOrEmpty(clave) ? null : clave);
            notaPantalla.Text = hecho ? "" : "Guardado. Hay un vídeo en marcha: la salida cambiará de pantalla la próxima vez que la abras.";
            Refrescar();
        };
        panel.Children.Add(pantallas);
        panel.Children.Add(notaPantalla);

        // --- Encuadre ---
        panel.Children.Add(Separador());
        panel.Children.Add(Dialogos.Rotulo("ENCUADRE DE LA FUNCIÓN"));
        var encuadres = new UniformGrid { Columns = 3 };
        foreach (var (valor, detalle) in new[]
                 {
                     (Encuadre.Completa, "Se ve todo; puede dejar bandas"),
                     (Encuadre.Llenar, "Sin negro; recorta los bordes"),
                     (Encuadre.SinBandas, "Quita las bandas que trae el vídeo"),
                 })
        {
            var contenido = new StackPanel { Spacing = 3 };
            contenido.Children.Add(new TextBlock { Text = Encuadres.Nombre(valor), FontSize = 13, FontWeight = FontWeight.SemiBold, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center });
            contenido.Children.Add(new TextBlock { Text = detalle, FontSize = 11, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, Opacity = 0.75 });
            var boton = new Button
            {
                Content = contenido,
                Margin = new Thickness(0, 0, 6, 0),
                Padding = new Thickness(8, 8),
                CornerRadius = new CornerRadius(6),
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Center,
            };
            boton.Click += (_, _) => motor.FijarEncuadreGeneral(valor);
            botonesEncuadre[valor] = boton;
            encuadres.Children.Add(boton);
        }
        panel.Children.Add(encuadres);
        panel.Children.Add(Nota("Cada pieza puede tener su propio encuadre en su menú ···."));
        panel.Children.Add(notaEncuadre);

        // --- Tamaño y posición ---
        panel.Children.Add(Separador());
        panel.Children.Add(Cabecera("TAMAÑO Y POSICIÓN", "Centrar", () => motor.CambiarAjuste(a =>
        {
            a.Zoom = 1;
            a.X = 0;
            a.Y = 0;
        })));
        panel.Children.Add(Barra("Tamaño", 1, 3, a => a.Zoom, (a, v) => a.Zoom = v, v => $"{Math.Round(v * 100)} %"));
        panel.Children.Add(Barra("Mover ← →", -1, 1, a => a.X, (a, v) => a.X = v, Lado("izquierda", "derecha")));
        panel.Children.Add(Barra("Mover ↑ ↓", -1, 1, a => a.Y, (a, v) => a.Y = v, Lado("arriba", "abajo")));
        panel.Children.Add(Nota("Mover sirve cuando la imagen es más grande que la pantalla: con más tamaño o con «Llenar la pantalla». Para correr todo el cuadro hacia un lado, usa los márgenes."));

        // --- Márgenes ---
        panel.Children.Add(Separador());
        panel.Children.Add(Cabecera("MÁRGENES", "Quitar márgenes", () => motor.CambiarAjuste(a =>
        {
            a.MargenArriba = 0;
            a.MargenAbajo = 0;
            a.MargenIzquierda = 0;
            a.MargenDerecha = 0;
        })));
        static string Porcentaje(double v) => $"{Math.Round(v * 100)} %";
        panel.Children.Add(Barra("Arriba", 0, 0.3, a => a.MargenArriba, (a, v) => a.MargenArriba = v, Porcentaje));
        panel.Children.Add(Barra("Abajo", 0, 0.3, a => a.MargenAbajo, (a, v) => a.MargenAbajo = v, Porcentaje));
        panel.Children.Add(Barra("Izquierda", 0, 0.3, a => a.MargenIzquierda, (a, v) => a.MargenIzquierda = v, Porcentaje));
        panel.Children.Add(Barra("Derecha", 0, 0.3, a => a.MargenDerecha, (a, v) => a.MargenDerecha = v, Porcentaje));
        panel.Children.Add(Nota("Encogen la proyección desde cada borde, por si la tela es más pequeña o algo tapa una parte. Fuera queda negro."));
        panel.Children.Add(Nota("¿La imagen sale torcida, más ancha arriba que abajo? Eso se corrige en el menú del propio proyector («keystone» o «trapecio»)."));

        // --- Pie ---
        var restablecer = Dialogos.Boton("Restablecer todo", Paleta.Panel);
        restablecer.Click += (_, _) =>
        {
            motor.RestablecerAjuste();
            motor.FijarEncuadreGeneral(Encuadre.Completa);
        };
        var cerrar = Dialogos.Boton("Cerrar", Paleta.Lima, oscuro: true, grande: true);
        cerrar.IsCancel = true;
        cerrar.Click += (_, _) => Close();
        var pie = new DockPanel { Margin = new Thickness(0, 6, 0, 0) };
        DockPanel.SetDock(cerrar, Dock.Right);
        pie.Children.Add(cerrar);
        pie.Children.Add(restablecer);
        panel.Children.Add(pie);

        Content = new ScrollViewer { Content = panel };

        motor.Cambio += Refrescar;
        Closed += (_, _) => motor.Cambio -= Refrescar;
        Opened += (_, _) => Refrescar();
    }

    private static TextBlock Nota(string texto = "") => new()
    {
        Text = texto,
        FontSize = 12,
        Foreground = Paleta.Tenue,
        TextWrapping = TextWrapping.Wrap,
    };

    private static Control Separador() => new Border { Height = 1, Background = Paleta.Panel };

    private static Control Cabecera(string rotulo, string accion, Action alPulsar)
    {
        var boton = Dialogos.Boton(accion, Paleta.Panel);
        boton.Click += (_, _) => alPulsar();
        var fila = new DockPanel();
        DockPanel.SetDock(boton, Dock.Right);
        fila.Children.Add(boton);
        var texto = Dialogos.Rotulo(rotulo);
        texto.VerticalAlignment = VerticalAlignment.Center;
        fila.Children.Add(texto);
        return fila;
    }

    private static Func<double, string> Lado(string negativo, string positivo) => v =>
        Math.Abs(v) < 0.005 ? "centro" : $"{Math.Round(Math.Abs(v) * 100)} % {(v < 0 ? negativo : positivo)}";

    private Control Barra(string nombre, double min, double max, Func<Ajuste, double> leer, Action<Ajuste, double> fijar, Func<double, string> texto)
    {
        var barra = new Slider { Minimum = min, Maximum = max, SmallChange = (max - min) / 100, LargeChange = (max - min) / 10 };
        var valor = new TextBlock { FontFamily = Paleta.Mono, FontSize = 12, Width = 120, TextAlignment = TextAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        barra.PropertyChanged += (_, e) =>
        {
            if (e.Property != RangeBase.ValueProperty || actualizando) return;
            var v = barra.Value;
            // Cerca del centro o del mínimo se queda justo en él: así es fácil volver.
            var reposo = min < 0 ? 0 : min;
            if (Math.Abs(v - reposo) < (max - min) * 0.015) v = reposo;
            motor.CambiarAjuste(a => fijar(a, v));
        };
        barras.Add((barra, valor, leer, texto));
        var rotulo = new TextBlock { Text = nombre, FontSize = 13, Width = 92, VerticalAlignment = VerticalAlignment.Center };
        var fila = new DockPanel();
        DockPanel.SetDock(rotulo, Dock.Left);
        DockPanel.SetDock(valor, Dock.Right);
        fila.Children.Add(rotulo);
        fila.Children.Add(valor);
        fila.Children.Add(barra);
        return fila;
    }

    private void Refrescar()
    {
        actualizando = true;
        try
        {
            // Imagen de prueba
            botonPrueba.Content = motor.Prueba ? "■  Quitar la imagen de prueba" : "▦  Proyectar la imagen de prueba";
            Dialogos.Estilo(botonPrueba, motor.Prueba ? Paleta.Lima : Paleta.Panel, oscuro: motor.Prueba, grande: true);
            botonPrueba.IsEnabled = motor.Prueba || !motor.EsVideo;
            ToolTip.SetTip(botonPrueba, motor.EsVideo && !motor.Prueba ? "Retira el vídeo para poner la imagen de prueba" : "Cuadrícula con bordes y centro para ajustar el proyector");

            // Pantallas
            var lista = control.PantallasDisponibles();
            var guardada = Motor.LeerPreferencia("pantallaSalida");
            var elementos = new List<ComboBoxItem> { new() { Content = "Automática: la que no es la de este control", Tag = "" } };
            ComboBoxItem? elegido = elementos[0];
            foreach (var (clave, nombre, propia, enUso) in lista)
            {
                var item = new ComboBoxItem { Content = nombre + (enUso ? " · salida aquí" : ""), Tag = clave, IsEnabled = !propia };
                if (clave == guardada && !propia) elegido = item;
                elementos.Add(item);
            }
            var firma = string.Join("|", elementos.Select(e => e.Content + "" + e.IsEnabled));
            if (pantallas.Tag as string != firma)
            {
                pantallas.Tag = firma;
                pantallas.ItemsSource = elementos;
                pantallas.SelectedItem = elegido;
            }
            if (lista.Count < 2 && string.IsNullOrEmpty(notaPantalla.Text))
            {
                notaPantalla.Text = "Solo hay una pantalla conectada. Conecta el proyector como pantalla ampliada (no duplicada) para elegirla aquí.";
            }
            else if (lista.Count >= 2 && notaPantalla.Text?.StartsWith("Solo hay una") == true)
            {
                notaPantalla.Text = "";
            }

            // Encuadre
            foreach (var (valor, boton) in botonesEncuadre)
            {
                var activo = motor.Funcion.Encuadre == valor;
                boton.Background = activo ? Paleta.Lima : Paleta.Panel;
                boton.Foreground = activo ? Paleta.Tinta : Paleta.Papel;
            }
            notaEncuadre.Text = motor.EsVideo && motor.EnPantalla is { } pieza
                ? $"En pantalla: «{pieza.Nombre}» · {Encuadres.Nombre(motor.EncuadreDe(pieza)).ToLowerInvariant()}"
                  + (pieza.Bandas is { } b ? " · bandas del archivo: " + b.Texto : motor.EncuadreDe(pieza) != Encuadre.Completa ? " · buscando bandas…" : "")
                : "";
            notaEncuadre.IsVisible = notaEncuadre.Text.Length > 0;

            // Barras
            foreach (var (barra, valor, leer, texto) in barras)
            {
                var v = leer(motor.Funcion.Ajuste);
                if (Math.Abs(barra.Value - v) > 0.0001) barra.Value = v;
                valor.Text = texto(v);
            }
        }
        finally
        {
            actualizando = false;
        }
    }
}
