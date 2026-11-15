using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Platform.Storage;

namespace Cabina;

/// La ventana del operador: lista a la izquierda, control de la proyección a la derecha.
public sealed class VentanaControl : Window
{
    private readonly Motor motor;
    private VentanaSalida? salida;

    private readonly TextBlock estadoSalida = new();
    private readonly Button botonSalida = new();
    private readonly TextBlock resumen = new();
    private readonly StackPanel filas = new() { Spacing = 1 };
    private readonly TextBlock vacio = new();
    private readonly Border franjaAviso = new();
    private readonly TextBlock textoAviso = new();
    private readonly TextBlock estado = new();
    private readonly TextBlock titulo = new();
    private readonly TextBlock restante = new();
    private readonly Slider barra = new();
    private readonly TextBlock transcurrido = new();
    private readonly TextBlock total = new();
    private readonly Button botonPausa = new();
    private readonly Button botonFondo = new();
    private readonly Slider volumen = new();
    private readonly TextBlock porcentaje = new();
    private readonly Button botonNegro = new();
    private readonly TextBlock nombreSiguiente = new();
    private readonly Button botonSiguiente = new();
    private bool arrastrando;
    private bool actualizando;

    public bool SalidaAbierta => salida != null;
    public bool SalidaEnProyector => salida?.EnProyector ?? false;

    public VentanaControl(Motor motor)
    {
        this.motor = motor;
        Title = "Cabina";
        Width = 1180;
        Height = 760;
        MinWidth = 940;
        MinHeight = 620;
        Background = Paleta.Tinta;
        Foreground = Paleta.Papel;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var raiz = new Grid
        {
            RowDefinitions = new RowDefinitions("Auto,Auto,*"),
            ColumnDefinitions = new ColumnDefinitions("420,*"),
        };
        var superior = BarraSuperior();
        Grid.SetColumnSpan(superior, 2);
        raiz.Children.Add(superior);

        MontarAviso();
        Grid.SetRow(franjaAviso, 1);
        Grid.SetColumnSpan(franjaAviso, 2);
        raiz.Children.Add(franjaAviso);

        var lista = PanelLista();
        Grid.SetRow(lista, 2);
        raiz.Children.Add(lista);

        var control = PanelControl();
        Grid.SetRow(control, 2);
        Grid.SetColumn(control, 1);
        raiz.Children.Add(control);
        Content = raiz;

        motor.AsegurarSalida = () =>
        {
            if (salida != null) return true;
            AbrirSalida();
            return false;
        };
        motor.Cambio += Refrescar;
        motor.CambioDeLista += RehacerLista;
        Closing += (_, _) => CerrarSalida();

        DragDrop.SetAllowDrop(this, true);
        AddHandler(DragDrop.DropEvent, AlSoltar);
        AddHandler(KeyDownEvent, AlPulsarTecla, RoutingStrategies.Tunnel);

        RehacerLista();
        Refrescar();
    }

    // ----- Construcción -----

    private Control BarraSuperior()
    {
        var marca = new TextBlock
        {
            Text = "CABINA",
            FontSize = 20,
            FontWeight = FontWeight.Black,
            LetterSpacing = 2,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var version = new TextBlock
        {
            Text = "prototipo multiplataforma · motor VLC",
            FontSize = 12,
            Foreground = Paleta.Tenue,
            Margin = new Thickness(14, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        estadoSalida.FontFamily = Paleta.Mono;
        estadoSalida.FontSize = 12;
        estadoSalida.FontWeight = FontWeight.SemiBold;
        estadoSalida.VerticalAlignment = VerticalAlignment.Center;
        estadoSalida.Margin = new Thickness(0, 0, 14, 0);
        Estilo(botonSalida, Paleta.Verde, oscuro: true);
        botonSalida.Click += (_, _) => AlternarSalida();

        var derecha = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        derecha.Children.Add(estadoSalida);
        derecha.Children.Add(botonSalida);
        var izquierda = new StackPanel { Orientation = Orientation.Horizontal };
        izquierda.Children.Add(marca);
        izquierda.Children.Add(version);

        var panel = new Grid { Margin = new Thickness(20, 12) };
        panel.Children.Add(izquierda);
        panel.Children.Add(derecha);
        return new Border
        {
            Child = panel,
            BorderBrush = Paleta.Panel,
            BorderThickness = new Thickness(0, 0, 0, 1),
        };
    }

    private void MontarAviso()
    {
        textoAviso.TextWrapping = TextWrapping.Wrap;
        textoAviso.Foreground = Paleta.Tinta;
        textoAviso.FontSize = 13;
        textoAviso.VerticalAlignment = VerticalAlignment.Center;
        var cerrar = new Button { Content = "Entendido" };
        Estilo(cerrar, Paleta.Tinta);
        cerrar.Click += (_, _) =>
        {
            motor.Aviso = null;
            Refrescar();
        };
        var fila = new DockPanel { Margin = new Thickness(20, 8) };
        DockPanel.SetDock(cerrar, Dock.Right);
        fila.Children.Add(cerrar);
        fila.Children.Add(textoAviso);
        franjaAviso.Child = fila;
        franjaAviso.Background = Paleta.Ambar;
        franjaAviso.IsVisible = false;
    }

    private Control PanelLista()
    {
        var rotulo = Rotulo("ORDEN DE LA FUNCIÓN");
        var anadir = new Button { Content = "+  Añadir" };
        Estilo(anadir, Paleta.Panel);
        anadir.Click += async (_, _) => await PedirArchivos();
        var cabecera = new DockPanel();
        DockPanel.SetDock(anadir, Dock.Right);
        cabecera.Children.Add(anadir);
        cabecera.Children.Add(rotulo);

        resumen.FontFamily = Paleta.Mono;
        resumen.FontSize = 13;
        resumen.Margin = new Thickness(0, 6, 0, 0);

        var arriba = new StackPanel { Margin = new Thickness(16, 14, 16, 12) };
        arriba.Children.Add(cabecera);
        arriba.Children.Add(resumen);

        vacio.Text = "La lista está vacía.\n\nPulsa Añadir o arrastra aquí tus vídeos e imágenes.\nCon el motor VLC se admiten también MKV, AVI, WMV y casi cualquier formato.";
        vacio.TextWrapping = TextWrapping.Wrap;
        vacio.TextAlignment = TextAlignment.Center;
        vacio.Foreground = Paleta.Tenue;
        vacio.FontSize = 13;
        vacio.Margin = new Thickness(30, 60, 30, 0);

        var cuerpo = new Panel();
        cuerpo.Children.Add(new ScrollViewer { Content = filas });
        cuerpo.Children.Add(vacio);

        var pie = Creditos();
        var panel = new DockPanel { Background = Paleta.Pizarra };
        DockPanel.SetDock(arriba, Dock.Top);
        DockPanel.SetDock(pie, Dock.Bottom);
        panel.Children.Add(arriba);
        panel.Children.Add(pie);
        panel.Children.Add(cuerpo);
        return panel;
    }

    private Control Creditos()
    {
        var fila = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Margin = new Thickness(16, 10) };
        try
        {
            using var flujo = AssetLoader.Open(new Uri("avares://Cabina/Recursos/muyuna.png"));
            fila.Children.Add(new Image { Source = new Bitmap(flujo), Height = 44 });
        }
        catch
        {
            // Sin logo la app funciona igual.
        }
        var textos = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        textos.Children.Add(new TextBlock { Text = "App desarrollada por", FontSize = 11, Foreground = Paleta.Tenue });
        textos.Children.Add(new TextBlock { Text = "Muyuna.org", FontSize = 13, FontWeight = FontWeight.SemiBold });
        fila.Children.Add(textos);
        return new Border { Child = fila, BorderBrush = Paleta.Panel, BorderThickness = new Thickness(0, 1, 0, 0) };
    }

    private Control PanelControl()
    {
        estado.FontFamily = Paleta.Mono;
        estado.FontSize = 13;
        estado.FontWeight = FontWeight.SemiBold;

        titulo.FontSize = 26;
        titulo.FontWeight = FontWeight.Bold;
        titulo.TextTrimming = TextTrimming.CharacterEllipsis;
        titulo.Margin = new Thickness(0, 4, 0, 0);

        restante.FontFamily = Paleta.Mono;
        restante.FontSize = 84;
        restante.FontWeight = FontWeight.SemiBold;
        restante.Margin = new Thickness(0, 6, 0, 0);

        barra.Minimum = 0;
        barra.Maximum = 1;
        barra.AddHandler(PointerPressedEvent, (_, _) => arrastrando = true, RoutingStrategies.Tunnel);
        barra.AddHandler(PointerReleasedEvent, (_, _) =>
        {
            if (!arrastrando) return;
            arrastrando = false;
            motor.Buscar(barra.Value);
        }, RoutingStrategies.Tunnel | RoutingStrategies.Bubble, handledEventsToo: true);

        transcurrido.FontFamily = Paleta.Mono;
        transcurrido.FontSize = 12;
        transcurrido.Foreground = Paleta.Tenue;
        total.FontFamily = Paleta.Mono;
        total.FontSize = 12;
        total.Foreground = Paleta.Tenue;
        total.HorizontalAlignment = HorizontalAlignment.Right;
        var tiempos = new Grid();
        tiempos.Children.Add(transcurrido);
        tiempos.Children.Add(total);

        Estilo(botonPausa, Paleta.Panel, grande: true);
        botonPausa.MinWidth = 120;
        ToolTip.SetTip(botonFondo, "Retira la pieza y deja la pantalla del público en negro");
        botonPausa.Click += (_, _) => motor.AlternarPausa();
        botonFondo.Content = "■  Quitar";
        Estilo(botonFondo, Paleta.Panel, grande: true);
        botonFondo.Click += (_, _) => motor.VolverAlFondo();

        volumen.Minimum = 0;
        volumen.Maximum = 1;
        volumen.Value = motor.Volumen;
        volumen.Width = 150;
        volumen.VerticalAlignment = VerticalAlignment.Center;
        volumen.PropertyChanged += (_, e) =>
        {
            if (e.Property == RangeBase.ValueProperty && !actualizando) motor.FijarVolumen(volumen.Value);
        };
        porcentaje.FontFamily = Paleta.Mono;
        porcentaje.FontSize = 12;
        porcentaje.Foreground = Paleta.Tenue;
        porcentaje.Width = 46;
        porcentaje.TextAlignment = TextAlignment.Right;
        porcentaje.VerticalAlignment = VerticalAlignment.Center;

        var sonido = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
        sonido.Children.Add(new TextBlock { Text = "Volumen", FontSize = 12, Foreground = Paleta.Tenue, VerticalAlignment = VerticalAlignment.Center });
        sonido.Children.Add(volumen);
        sonido.Children.Add(porcentaje);
        var botones = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        botones.Children.Add(botonPausa);
        botones.Children.Add(botonFondo);
        var transporte = new Grid { Margin = new Thickness(0, 14, 0, 0) };
        transporte.Children.Add(botones);
        transporte.Children.Add(sonido);

        botonNegro.HorizontalAlignment = HorizontalAlignment.Stretch;
        botonNegro.HorizontalContentAlignment = HorizontalAlignment.Left;
        botonNegro.FontSize = 18;
        botonNegro.FontWeight = FontWeight.Bold;
        botonNegro.Padding = new Thickness(18, 16);
        botonNegro.CornerRadius = new CornerRadius(8);
        botonNegro.BorderThickness = new Thickness(1.5);
        botonNegro.Margin = new Thickness(0, 14, 0, 0);
        botonNegro.Click += (_, _) => motor.AlternarNegro();

        nombreSiguiente.FontSize = 15;
        nombreSiguiente.FontWeight = FontWeight.SemiBold;
        nombreSiguiente.TextTrimming = TextTrimming.CharacterEllipsis;
        nombreSiguiente.VerticalAlignment = VerticalAlignment.Center;
        nombreSiguiente.Margin = new Thickness(12, 0);
        botonSiguiente.Content = "▶▶  Lanzarla";
        Estilo(botonSiguiente, Paleta.Panel);
        botonSiguiente.Click += (_, _) => motor.LanzarSiguiente();
        var rotuloSiguiente = Rotulo("A CONTINUACIÓN");
        rotuloSiguiente.VerticalAlignment = VerticalAlignment.Center;
        var continuacion = new DockPanel { Margin = new Thickness(0, 16, 0, 0) };
        DockPanel.SetDock(rotuloSiguiente, Dock.Left);
        DockPanel.SetDock(botonSiguiente, Dock.Right);
        continuacion.Children.Add(rotuloSiguiente);
        continuacion.Children.Add(botonSiguiente);
        continuacion.Children.Add(nombreSiguiente);

        var nota = new TextBlock
        {
            Text = "Prototipo para validar el motor VLC en Windows y Mac. Atajos: Espacio pausa · Ctrl+B negro · Ctrl+→ siguiente.",
            FontSize = 12,
            Foreground = Paleta.Tenue,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 18, 0, 0),
        };

        var panel = new StackPanel { Margin = new Thickness(22, 20) };
        panel.Children.Add(Rotulo("LO QUE VE EL PÚBLICO"));
        panel.Children.Add(new Border { Height = 6 });
        panel.Children.Add(estado);
        panel.Children.Add(titulo);
        panel.Children.Add(Rotulo("RESTANTE", new Thickness(0, 14, 0, 0)));
        panel.Children.Add(restante);
        panel.Children.Add(barra);
        panel.Children.Add(tiempos);
        panel.Children.Add(transporte);
        panel.Children.Add(botonNegro);
        panel.Children.Add(new Border { Height = 1, Background = Paleta.Panel, Margin = new Thickness(0, 16, 0, 0) });
        panel.Children.Add(continuacion);
        panel.Children.Add(nota);
        return new ScrollViewer { Content = panel };
    }

    private static TextBlock Rotulo(string texto, Thickness? margen = null) => new()
    {
        Text = texto,
        FontFamily = Paleta.Mono,
        FontSize = 11,
        FontWeight = FontWeight.SemiBold,
        Foreground = Paleta.Tenue,
        Margin = margen ?? new Thickness(0),
    };

    private static void Estilo(Button boton, IBrush fondo, bool oscuro = false, bool grande = false)
    {
        boton.Background = fondo;
        boton.Foreground = oscuro ? Paleta.Tinta : Paleta.Papel;
        boton.FontSize = grande ? 14 : 13;
        boton.FontWeight = FontWeight.SemiBold;
        boton.Padding = grande ? new Thickness(14, 9) : new Thickness(10, 6);
        boton.CornerRadius = new CornerRadius(6);
        boton.VerticalAlignment = VerticalAlignment.Center;
    }

    // ----- Salida -----

    public void AlternarSalida()
    {
        if (salida == null) AbrirSalida(); else CerrarSalida();
    }

    public void AbrirSalida()
    {
        if (salida != null) return;
        var nueva = new VentanaSalida(motor, PantallaProyector());
        nueva.Closed += (_, _) =>
        {
            if (salida == nueva) salida = null;
            Refrescar();
        };
        salida = nueva;
        nueva.Show();
        Refrescar();
    }

    public void CerrarSalida()
    {
        var abierta = salida;
        if (abierta == null) return;
        salida = null;
        abierta.Close();
        Refrescar();
    }

    /// La pantalla que no es la del operador, si hay más de una.
    private Screen? PantallaProyector()
    {
        var todas = Screens.All;
        if (todas.Count < 2) return null;
        var propia = Screens.ScreenFromWindow(this) ?? Screens.Primary;
        return todas.FirstOrDefault(p => propia == null || p.Bounds != propia.Bounds);
    }

    // ----- Entrada -----

    private async Task PedirArchivos()
    {
        var patrones = Motor.ExtensionesVideo.Concat(Motor.ExtensionesImagen).Select(e => "*." + e).ToList();
        var elegidos = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Añadir vídeos e imágenes",
            AllowMultiple = true,
            FileTypeFilter = new[] { new FilePickerFileType("Vídeos e imágenes") { Patterns = patrones } },
        });
        var rutas = elegidos.Select(a => a.TryGetLocalPath()).Where(r => !string.IsNullOrEmpty(r)).Select(r => r!).ToList();
        if (rutas.Count > 0) motor.Agregar(rutas);
    }

    private void AlSoltar(object? sender, DragEventArgs e)
    {
        var archivos = e.Data.GetFiles();
        if (archivos == null) return;
        var rutas = archivos.Select(a => a.TryGetLocalPath()).Where(r => !string.IsNullOrEmpty(r)).Select(r => r!).ToList();
        if (rutas.Count > 0) motor.Agregar(rutas);
    }

    private void AlPulsarTecla(object? sender, KeyEventArgs e)
    {
        var orden = e.KeyModifiers.HasFlag(KeyModifiers.Control) || e.KeyModifiers.HasFlag(KeyModifiers.Meta);
        if (e.Key == Key.Space && !orden)
        {
            if (!motor.EsVideo) return;
            motor.AlternarPausa();
            e.Handled = true;
        }
        else if (e.Key == Key.B && orden)
        {
            motor.AlternarNegro();
            e.Handled = true;
        }
        else if (e.Key == Key.Right && orden)
        {
            motor.LanzarSiguiente();
            e.Handled = true;
        }
    }

    // ----- Refresco -----

    private void RehacerLista()
    {
        filas.Children.Clear();
        var numero = 0;
        foreach (var pieza in motor.Piezas)
        {
            numero++;
            filas.Children.Add(Fila(pieza, numero));
        }
        vacio.IsVisible = motor.Piezas.Count == 0;
        var n = motor.Piezas.Count;
        resumen.Text = $"{(n == 1 ? "1 pieza" : n + " piezas")} · {Motor.TextoDeTiempo(motor.DuracionTotal)} de vídeo";
    }

    private Control Fila(Pieza pieza, int numero)
    {
        var enPantalla = motor.EnPantalla == pieza;
        var seleccionada = motor.Seleccion == pieza.Id;

        var indice = new TextBlock
        {
            Text = numero.ToString("00"),
            FontFamily = Paleta.Mono,
            FontSize = 13,
            Foreground = enPantalla ? Paleta.Ambar : Paleta.Tenue,
            VerticalAlignment = VerticalAlignment.Center,
            Width = 30,
        };
        var nombre = new TextBlock
        {
            Text = pieza.Nombre,
            FontSize = 14,
            FontWeight = FontWeight.Medium,
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        var baseDetalle = pieza.Tipo == TipoPieza.Video
            ? (pieza.Duracion is { } d ? Motor.TextoDeTiempo(d) : "--:--") + " · " + Path.GetExtension(pieza.Ruta).TrimStart('.').ToUpperInvariant()
            : "Imagen fija";
        var detalle = new TextBlock
        {
            Text = enPantalla ? "EN PANTALLA · " + baseDetalle : pieza.Pasada ? "Ya pasó · " + baseDetalle : baseDetalle,
            FontFamily = Paleta.Mono,
            FontSize = 11,
            Foreground = enPantalla ? Paleta.Ambar : Paleta.Tenue,
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        var textos = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 2 };
        textos.Children.Add(nombre);
        textos.Children.Add(detalle);

        var lanzar = new Button { Content = "▶  Lanzar" };
        Estilo(lanzar, enPantalla ? Paleta.Panel : Paleta.Ambar, oscuro: !enPantalla);
        lanzar.Click += (_, _) => motor.Lanzar(pieza);

        var menu = new MenuFlyout();
        var subir = new MenuItem { Header = "Subir" };
        subir.Click += (_, _) => motor.Mover(pieza, -1);
        var bajar = new MenuItem { Header = "Bajar" };
        bajar.Click += (_, _) => motor.Mover(pieza, 1);
        var quitar = new MenuItem { Header = "Quitar de la lista" };
        quitar.Click += (_, _) => motor.Quitar(pieza);
        menu.Items.Add(subir);
        menu.Items.Add(bajar);
        menu.Items.Add(new Separator());
        menu.Items.Add(quitar);
        var mas = new Button { Content = "···", Flyout = menu };
        Estilo(mas, Brushes.Transparent);

        var rejilla = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto,Auto"), Margin = new Thickness(16, 9, 10, 9) };
        rejilla.Children.Add(indice);
        Grid.SetColumn(textos, 1);
        rejilla.Children.Add(textos);
        Grid.SetColumn(lanzar, 2);
        lanzar.Margin = new Thickness(8, 0, 4, 0);
        rejilla.Children.Add(lanzar);
        Grid.SetColumn(mas, 3);
        rejilla.Children.Add(mas);

        var marco = new Border
        {
            Child = rejilla,
            Background = enPantalla ? Paleta.AmbarSuave : seleccionada ? Paleta.Panel : Paleta.Pizarra,
            Opacity = pieza.Pasada && !enPantalla ? 0.55 : 1,
        };
        marco.PointerPressed += (_, _) =>
        {
            motor.Seleccion = pieza.Id;
            RehacerLista();
        };
        return marco;
    }

    private void Refrescar()
    {
        actualizando = true;
        try
        {
            var abierta = salida != null;
            estadoSalida.Text = !abierta ? "SIN SALIDA" : SalidaEnProyector ? "SALIDA EN EL PROYECTOR" : "SALIDA EN VENTANA DE PRUEBA";
            estadoSalida.Foreground = abierta ? Paleta.Verde : Paleta.Tenue;
            botonSalida.Content = abierta ? "Cerrar salida" : "Abrir salida";
            Estilo(botonSalida, abierta ? Paleta.Panel : Paleta.Verde, oscuro: !abierta);

            franjaAviso.IsVisible = !string.IsNullOrEmpty(motor.Aviso);
            textoAviso.Text = motor.Aviso ?? "";

            estado.Text = motor.Negro ? "● PANTALLA EN NEGRO"
                : motor.EsVideo ? (motor.Reproduciendo ? "▶ VÍDEO EN PANTALLA" : "❚❚ PAUSADO")
                : motor.EsImagen ? "■ IMAGEN EN PANTALLA"
                : "● PANTALLA EN NEGRO";
            estado.Foreground = motor.EnPantalla != null && !motor.Negro ? Paleta.Ambar : Paleta.Tenue;
            titulo.Text = motor.EnPantalla?.Nombre ?? "Ninguna pieza en pantalla";

            restante.Text = motor.EsVideo ? "-" + Motor.TextoDeTiempo(motor.Restante) : "--:--";
            restante.Foreground = !motor.EsVideo ? Paleta.Tenue : motor.Restante <= 30 ? Paleta.Ambar : Paleta.Papel;

            barra.IsEnabled = motor.EsVideo && motor.Duracion > 0;
            barra.Maximum = Math.Max(motor.Duracion, 1);
            if (!arrastrando) barra.Value = Math.Min(motor.Tiempo, barra.Maximum);
            transcurrido.Text = Motor.TextoDeTiempo(motor.Tiempo);
            total.Text = Motor.TextoDeTiempo(motor.Duracion);

            botonPausa.Content = motor.Reproduciendo ? "❚❚  Pausar" : "▶  Reanudar";
            botonPausa.IsEnabled = motor.EsVideo;
            botonFondo.IsEnabled = motor.EnPantalla != null;
            if (Math.Abs(volumen.Value - motor.Volumen) > 0.001) volumen.Value = motor.Volumen;
            porcentaje.Text = (int)Math.Round(motor.Volumen * 100) + " %";

            botonNegro.Content = motor.Negro ? "☀  QUITAR NEGRO" : "●  NEGRO";
            botonNegro.Background = motor.Negro ? Paleta.Ambar : Brushes.Black;
            botonNegro.Foreground = motor.Negro ? Paleta.Tinta : Paleta.Papel;
            botonNegro.BorderBrush = motor.Negro ? Paleta.Ambar : Paleta.Tenue;

            var siguiente = motor.Siguiente;
            nombreSiguiente.Text = siguiente?.Nombre ?? (motor.Piezas.Count == 0 ? "Añade piezas a la lista" : "Fin de la lista");
            nombreSiguiente.Foreground = siguiente != null ? Paleta.Papel : Paleta.Tenue;
            botonSiguiente.IsEnabled = siguiente != null;
        }
        finally
        {
            actualizando = false;
        }
    }
}
