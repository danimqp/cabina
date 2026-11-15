using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform;
using Avalonia.Platform.Storage;
using Avalonia.Threading;

namespace Proyectapp;

/// La ventana del operador: lista a la izquierda; proyección, mensajes y sala a la derecha.
public sealed class VentanaControl : Window
{
    private readonly Motor motor;
    private VentanaSalida? salida;
    private Window? mini;
    private TextBlock? miniTitulo;
    private TextBlock? miniRestante;
    private Button? miniPausa;
    private Button? miniNegro;
    private bool cierreConfirmado;
    private bool arrastrando;
    private bool actualizando;

    // Barra superior
    private readonly TextBox nombreFuncion = new();
    private readonly TextBlock estadoSalida = new();
    private readonly Button botonSalida = new();
    // Avisos
    private readonly Border franjaAviso = new();
    private readonly TextBlock textoAviso = new();
    // Lista
    private readonly TextBlock resumen = new();
    private readonly TextBlock horaFin = new();
    private readonly TextBlock nota = new();
    private readonly Button botonComprobar = new();
    private readonly StackPanel filas = new() { Spacing = 1 };
    private readonly TextBlock vacio = new();
    // Proyección
    private readonly Image previa = new() { Stretch = Stretch.Uniform };
    private readonly Border marcoPrevia = new();
    private readonly TextBlock avisoSalida = new();
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
    private readonly TextBox mensaje = new();
    private readonly Button botonMostrar = new();
    private readonly Button botonALaLista = new();
    private readonly TextBlock nombreSiguiente = new();
    private readonly TextBlock detalleSiguiente = new();
    private readonly Button botonSiguiente = new();
    // Sala
    private readonly TextBlock nombreMusica = new();
    private readonly TextBlock estadoMusica = new();
    private readonly Button botonMusica = new();
    private readonly Slider volumenMusica = new();
    private readonly TextBlock nombreFondo = new();
    private readonly Button botonQuitarFondo = new();
    private readonly ComboBox salidaSonido = new();

    public bool SalidaAbierta => salida != null;
    public bool SalidaEnProyector => salida?.EnProyector ?? false;
    public bool MiniVisible => mini?.IsVisible ?? false;

    public VentanaControl(Motor motor)
    {
        this.motor = motor;
        Title = "Proyectapp";
        Width = 1240;
        Height = 820;
        MinWidth = 1000;
        MinHeight = 680;
        Background = Paleta.Tinta;
        Foreground = Paleta.Papel;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var raiz = new Grid
        {
            RowDefinitions = new RowDefinitions("Auto,Auto,*"),
            ColumnDefinitions = new ColumnDefinitions("38*,62*"),
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

        Closing += AlCerrar;
        Opened += (_, _) =>
        {
            Plataforma.InstalarAtajosGlobales(this, motor.AlternarNegro, motor.AlternarPausa);
            Focus();
        };
        Deactivated += (_, _) => Dispatcher.UIThread.Post(MostrarMiniSiProcede, DispatcherPriority.Background);
        Activated += (_, _) =>
        {
            mini?.Hide();
            motor.VerificarArchivos();
            motor.ActualizarDispositivos();
        };

        DragDrop.SetAllowDrop(this, true);
        AddHandler(DragDrop.DropEvent, AlSoltar);
        AddHandler(KeyDownEvent, AlPulsarTecla, RoutingStrategies.Tunnel);

        RehacerLista();
        Refrescar();
    }

    // =================== Construcción ===================

    private Control BarraSuperior()
    {
        var izquierda = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        if (Dialogos.Recurso("icono.png") is { } icono)
        {
            izquierda.Children.Add(new Border
            {
                Background = Paleta.Papel,
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(4),
                VerticalAlignment = VerticalAlignment.Center,
                Child = new Image { Source = icono, Height = 30, Width = 30 },
            });
        }
        if (Dialogos.Recurso("nombre.png") is { } rotulo)
        {
            izquierda.Children.Add(new Image { Source = rotulo, Height = 26, VerticalAlignment = VerticalAlignment.Center });
        }
        else
        {
            izquierda.Children.Add(new TextBlock { Text = "Proyectapp", FontSize = 20, FontWeight = FontWeight.Black, VerticalAlignment = VerticalAlignment.Center });
        }

        nombreFuncion.Watermark = "Nombre de la función";
        nombreFuncion.FontSize = 14;
        nombreFuncion.Width = 260;
        nombreFuncion.Background = Brushes.Transparent;
        nombreFuncion.BorderThickness = new Thickness(0);
        nombreFuncion.Foreground = Paleta.Tenue;
        nombreFuncion.VerticalAlignment = VerticalAlignment.Center;
        nombreFuncion.LostFocus += (_, _) => motor.FijarNombreDeFuncion(nombreFuncion.Text ?? "");
        nombreFuncion.KeyDown += (_, e) =>
        {
            if (e.Key is Key.Enter or Key.Escape) Focus();
        };
        izquierda.Children.Add(nombreFuncion);

        var funcion = Dialogos.Boton("Función  ▾", Paleta.Panel);
        var menu = new MenuFlyout();
        menu.Items.Add(Entrada("Nueva función", async () => await NuevaFuncion()));
        menu.Items.Add(Entrada("Abrir función…", async () => await AbrirFuncion()));
        menu.Items.Add(Entrada("Guardar función como…", async () => await GuardarFuncion()));
        menu.Items.Add(new Separator());
        menu.Items.Add(Entrada("Reunir archivos en una carpeta…", async () => await ReunirArchivos()));
        funcion.Flyout = menu;
        ToolTip.SetTip(funcion, "Guardar, abrir y reunir los archivos de la función");

        var ayuda = Dialogos.Boton("?  Ayuda", Paleta.Panel);
        ayuda.Click += (_, _) => Dialogos.Ayuda(this);

        estadoSalida.FontFamily = Paleta.Mono;
        estadoSalida.FontSize = 12;
        estadoSalida.FontWeight = FontWeight.SemiBold;
        estadoSalida.VerticalAlignment = VerticalAlignment.Center;
        botonSalida.Click += async (_, _) => await AlternarSalida();
        ToolTip.SetTip(botonSalida, "Abre la pantalla del público en el proyector");

        var derecha = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, HorizontalAlignment = HorizontalAlignment.Right };
        derecha.Children.Add(funcion);
        derecha.Children.Add(ayuda);
        derecha.Children.Add(estadoSalida);
        derecha.Children.Add(botonSalida);

        var panel = new Grid { Margin = new Thickness(18, 10) };
        panel.Children.Add(izquierda);
        panel.Children.Add(derecha);
        return new Border { Child = panel, BorderBrush = Paleta.Panel, BorderThickness = new Thickness(0, 0, 0, 1) };
    }

    private static MenuItem Entrada(string texto, Action accion, bool habilitada = true)
    {
        var entrada = new MenuItem { Header = texto, IsEnabled = habilitada };
        entrada.Click += (_, _) => accion();
        return entrada;
    }

    private void MontarAviso()
    {
        textoAviso.TextWrapping = TextWrapping.Wrap;
        textoAviso.Foreground = Paleta.Tinta;
        textoAviso.FontSize = 13;
        textoAviso.VerticalAlignment = VerticalAlignment.Center;
        var cerrar = Dialogos.Boton("Entendido", Paleta.Tinta);
        cerrar.Click += (_, _) =>
        {
            motor.Aviso = null;
            Refrescar();
        };
        var fila = new DockPanel { Margin = new Thickness(18, 8) };
        DockPanel.SetDock(cerrar, Dock.Right);
        fila.Children.Add(cerrar);
        fila.Children.Add(textoAviso);
        franjaAviso.Child = fila;
        franjaAviso.Background = Paleta.Ambar;
        franjaAviso.IsVisible = false;
    }

    private Control PanelLista()
    {
        var anadir = Dialogos.Boton("+  Añadir", Paleta.Panel);
        anadir.Click += async (_, _) => await PedirArchivos();
        botonComprobar.Content = "Comprobar";
        Dialogos.Estilo(botonComprobar, Paleta.Panel);
        botonComprobar.Click += (_, _) => motor.Comprobar(avisar: true);
        ToolTip.SetTip(botonComprobar, "Abre cada archivo y avisa de los que no se van a poder proyectar");
        var botones = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        botones.Children.Add(botonComprobar);
        botones.Children.Add(anadir);
        var cabecera = new DockPanel();
        DockPanel.SetDock(botones, Dock.Right);
        cabecera.Children.Add(botones);
        var rotulo = Dialogos.Rotulo("ORDEN DE LA FUNCIÓN");
        rotulo.VerticalAlignment = VerticalAlignment.Center;
        cabecera.Children.Add(rotulo);

        resumen.FontFamily = Paleta.Mono;
        resumen.FontSize = 13;
        horaFin.FontFamily = Paleta.Mono;
        horaFin.FontSize = 11;
        horaFin.Foreground = Paleta.Tenue;
        nota.FontSize = 11;
        nota.Foreground = Paleta.Lima;
        nota.TextWrapping = TextWrapping.Wrap;

        var arriba = new StackPanel { Margin = new Thickness(16, 12, 16, 10), Spacing = 4 };
        arriba.Children.Add(cabecera);
        arriba.Children.Add(resumen);
        arriba.Children.Add(horaFin);
        arriba.Children.Add(nota);

        vacio.Text = "La lista está vacía.\n\nPulsa Añadir o arrastra aquí tus vídeos e imágenes.\nSe admite casi cualquier formato: MP4, MOV, MKV, AVI, WMV…";
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
        var fila = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Margin = new Thickness(16, 8) };
        if (Dialogos.Recurso("muyuna.png") is { } logo) fila.Children.Add(new Image { Source = logo, Height = 42 });
        var textos = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        textos.Children.Add(new TextBlock { Text = "App desarrollada por", FontSize = 11, Foreground = Paleta.Tenue });
        textos.Children.Add(new TextBlock { Text = "Muyuna.org", FontSize = 13, FontWeight = FontWeight.SemiBold });
        fila.Children.Add(textos);
        return new Border { Child = fila, BorderBrush = Paleta.Panel, BorderThickness = new Thickness(0, 1, 0, 0) };
    }

    private Control PanelControl()
    {
        // --- Lo que ve el público, estado y cuenta atrás ---
        marcoPrevia.Background = Brushes.Black;
        marcoPrevia.CornerRadius = new CornerRadius(6);
        marcoPrevia.BorderThickness = new Thickness(2);
        marcoPrevia.ClipToBounds = true;
        marcoPrevia.Child = previa;
        var caja = new Viewbox { Stretch = Stretch.Uniform, Child = new Border { Width = 320, Height = 180, Child = marcoPrevia } };
        avisoSalida.FontSize = 11;
        avisoSalida.Foreground = Paleta.Ambar;
        avisoSalida.Text = "Salida cerrada: el público aún no ve nada";
        var columnaPrevia = new StackPanel { Spacing = 6 };
        columnaPrevia.Children.Add(Dialogos.Rotulo("LO QUE VE EL PÚBLICO"));
        columnaPrevia.Children.Add(caja);
        columnaPrevia.Children.Add(avisoSalida);

        estado.FontFamily = Paleta.Mono;
        estado.FontSize = 13;
        estado.FontWeight = FontWeight.SemiBold;
        titulo.FontSize = 22;
        titulo.FontWeight = FontWeight.Bold;
        titulo.TextWrapping = TextWrapping.Wrap;
        titulo.MaxLines = 2;
        titulo.TextTrimming = TextTrimming.CharacterEllipsis;
        restante.FontFamily = Paleta.Mono;
        restante.FontSize = 64;
        restante.FontWeight = FontWeight.SemiBold;
        var columnaEstado = new StackPanel { Spacing = 4, Margin = new Thickness(18, 18, 0, 0) };
        columnaEstado.Children.Add(estado);
        columnaEstado.Children.Add(titulo);
        columnaEstado.Children.Add(new Border { Height = 6 });
        columnaEstado.Children.Add(Dialogos.Rotulo("RESTANTE"));
        columnaEstado.Children.Add(restante);

        var cabeza = new Grid { ColumnDefinitions = new ColumnDefinitions("55*,45*") };
        cabeza.Children.Add(columnaPrevia);
        Grid.SetColumn(columnaEstado, 1);
        cabeza.Children.Add(columnaEstado);

        // --- Barra de tiempo ---
        barra.Minimum = 0;
        barra.Maximum = 1;
        barra.AddHandler(PointerPressedEvent, (_, _) => arrastrando = true, RoutingStrategies.Tunnel);
        barra.AddHandler(PointerReleasedEvent, (_, _) =>
        {
            if (!arrastrando) return;
            arrastrando = false;
            motor.Buscar(barra.Value);
        }, RoutingStrategies.Tunnel | RoutingStrategies.Bubble, handledEventsToo: true);
        foreach (var texto in new[] { transcurrido, total })
        {
            texto.FontFamily = Paleta.Mono;
            texto.FontSize = 12;
            texto.Foreground = Paleta.Tenue;
        }
        total.HorizontalAlignment = HorizontalAlignment.Right;
        var tiempos = new Grid();
        tiempos.Children.Add(transcurrido);
        tiempos.Children.Add(total);

        // --- Transporte y volumen ---
        Dialogos.Estilo(botonPausa, Paleta.Panel, grande: true);
        botonPausa.MinWidth = 120;
        botonPausa.Click += (_, _) => motor.AlternarPausa();
        ToolTip.SetTip(botonPausa, "Barra espaciadora");
        botonFondo.Content = "■  Volver al fondo";
        Dialogos.Estilo(botonFondo, Paleta.Panel, grande: true);
        botonFondo.Click += (_, _) => motor.VolverAlFondo();
        ToolTip.SetTip(botonFondo, "Retira la pieza y deja la imagen de fondo o negro");
        volumen.Minimum = 0;
        volumen.Maximum = 1;
        volumen.Width = 140;
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
        var transporte = new Grid();
        transporte.Children.Add(botones);
        transporte.Children.Add(sonido);

        // --- Negro ---
        botonNegro.HorizontalAlignment = HorizontalAlignment.Stretch;
        botonNegro.HorizontalContentAlignment = HorizontalAlignment.Left;
        botonNegro.FontSize = 18;
        botonNegro.FontWeight = FontWeight.Bold;
        botonNegro.Padding = new Thickness(18, 14);
        botonNegro.CornerRadius = new CornerRadius(8);
        botonNegro.BorderThickness = new Thickness(1.5);
        botonNegro.Click += (_, _) => motor.AlternarNegro();
        ToolTip.SetTip(botonNegro, "Tapa la pantalla al instante sin perder el punto del vídeo");

        // --- Mensaje rápido y cuenta atrás ---
        mensaje.Watermark = "Mensaje rápido: «Hoy, conversatorio»";
        mensaje.FontSize = 14;
        mensaje.VerticalAlignment = VerticalAlignment.Center;
        mensaje.KeyDown += async (_, e) =>
        {
            if (e.Key != Key.Enter) return;
            e.Handled = true;
            await MostrarMensaje();
        };
        mensaje.PropertyChanged += (_, e) =>
        {
            if (e.Property == TextBox.TextProperty) RefrescarMensaje();
        };
        botonMostrar.Content = "Mostrar";
        Dialogos.Estilo(botonMostrar, Paleta.Lima, oscuro: true);
        botonMostrar.Click += async (_, _) => await MostrarMensaje();
        ToolTip.SetTip(botonMostrar, "Muestra el texto en el proyector, en grande sobre negro");
        var cuenta = Dialogos.Boton("Cuenta atrás  ▾", Paleta.Panel);
        var minutos = new MenuFlyout();
        foreach (var m in new[] { 1, 3, 5, 10, 15, 20, 30 })
        {
            var cantidad = m;
            minutos.Items.Add(Entrada(m == 1 ? "1 minuto" : m + " minutos", async () => await IniciarCuenta(cantidad)));
        }
        cuenta.Flyout = minutos;
        ToolTip.SetTip(cuenta, "Muestra una cuenta atrás. Si has escrito un texto, sale encima («Volvemos en»); si no, «Empezamos en».");
        botonALaLista.Content = "+  A la lista";
        Dialogos.Estilo(botonALaLista, Paleta.Tinta);
        botonALaLista.Click += (_, _) =>
        {
            motor.AgregarMensaje(mensaje.Text ?? "");
            mensaje.Text = "";
        };
        ToolTip.SetTip(botonALaLista, "Guarda el mensaje como pieza de la lista para usarlo más tarde");
        var accionesMensaje = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(8, 0, 0, 0) };
        accionesMensaje.Children.Add(botonMostrar);
        accionesMensaje.Children.Add(cuenta);
        accionesMensaje.Children.Add(botonALaLista);
        var filaMensaje = new DockPanel();
        DockPanel.SetDock(accionesMensaje, Dock.Right);
        filaMensaje.Children.Add(accionesMensaje);
        filaMensaje.Children.Add(mensaje);
        var cajaMensaje = new Border { Background = Paleta.Panel, CornerRadius = new CornerRadius(8), Padding = new Thickness(10, 8), Child = filaMensaje };

        // --- A continuación ---
        nombreSiguiente.FontSize = 15;
        nombreSiguiente.FontWeight = FontWeight.SemiBold;
        nombreSiguiente.TextTrimming = TextTrimming.CharacterEllipsis;
        nombreSiguiente.VerticalAlignment = VerticalAlignment.Center;
        nombreSiguiente.Margin = new Thickness(12, 0, 8, 0);
        detalleSiguiente.FontFamily = Paleta.Mono;
        detalleSiguiente.FontSize = 12;
        detalleSiguiente.Foreground = Paleta.Tenue;
        detalleSiguiente.VerticalAlignment = VerticalAlignment.Center;
        botonSiguiente.Content = "▶▶  Lanzarla";
        Dialogos.Estilo(botonSiguiente, Paleta.Panel);
        botonSiguiente.Click += async (_, _) =>
        {
            if (motor.Siguiente is { } pieza) await PedirLanzar(pieza);
        };
        var rotuloSiguiente = Dialogos.Rotulo("A CONTINUACIÓN");
        rotuloSiguiente.VerticalAlignment = VerticalAlignment.Center;
        var continuacion = new DockPanel();
        DockPanel.SetDock(rotuloSiguiente, Dock.Left);
        DockPanel.SetDock(botonSiguiente, Dock.Right);
        DockPanel.SetDock(detalleSiguiente, Dock.Right);
        continuacion.Children.Add(rotuloSiguiente);
        continuacion.Children.Add(botonSiguiente);
        continuacion.Children.Add(detalleSiguiente);
        continuacion.Children.Add(nombreSiguiente);

        var panel = new StackPanel { Margin = new Thickness(20, 16), Spacing = 12 };
        panel.Children.Add(cabeza);
        var bloqueTiempo = new StackPanel();
        bloqueTiempo.Children.Add(barra);
        bloqueTiempo.Children.Add(tiempos);
        panel.Children.Add(bloqueTiempo);
        panel.Children.Add(transporte);
        panel.Children.Add(botonNegro);
        panel.Children.Add(cajaMensaje);
        panel.Children.Add(new Border { Height = 1, Background = Paleta.Panel });
        panel.Children.Add(continuacion);
        panel.Children.Add(new Border { Height = 1, Background = Paleta.Panel });
        panel.Children.Add(Sala());
        return new ScrollViewer { Content = panel };
    }

    /// Música de espera, fondo entre vídeos y salida de sonido: siempre a la vista.
    private Control Sala()
    {
        TextBlock Nombre(TextBlock texto)
        {
            texto.FontSize = 15;
            texto.FontWeight = FontWeight.SemiBold;
            texto.TextTrimming = TextTrimming.CharacterEllipsis;
            return texto;
        }
        TextBlock Detalle(string texto) => new() { Text = texto, FontSize = 12, Foreground = Paleta.Tenue, TextWrapping = TextWrapping.Wrap };

        // Música de espera
        estadoMusica.FontSize = 12;
        Dialogos.Estilo(botonMusica, Paleta.Panel);
        botonMusica.Click += async (_, _) =>
        {
            if (motor.Funcion.Musica.Count == 0 && !motor.MusicaEncendida) await PedirMusica();
            else motor.AlternarMusica();
        };
        var elegirMusica = Dialogos.Boton("Elegir…", Paleta.Panel);
        elegirMusica.Click += async (_, _) => await PedirMusica();
        var botonesMusica = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        botonesMusica.Children.Add(botonMusica);
        botonesMusica.Children.Add(elegirMusica);
        volumenMusica.Minimum = 0;
        volumenMusica.Maximum = 1;
        volumenMusica.MaxWidth = 160;
        volumenMusica.HorizontalAlignment = HorizontalAlignment.Left;
        volumenMusica.Width = 150;
        volumenMusica.PropertyChanged += (_, e) =>
        {
            if (e.Property == RangeBase.ValueProperty && !actualizando) motor.FijarVolumenMusica(volumenMusica.Value);
        };
        ToolTip.SetTip(volumenMusica, "Volumen de la música de espera");
        var musica = new StackPanel { Spacing = 5 };
        musica.Children.Add(Dialogos.Rotulo("MÚSICA DE ESPERA"));
        musica.Children.Add(Nombre(nombreMusica));
        musica.Children.Add(estadoMusica);
        musica.Children.Add(botonesMusica);
        musica.Children.Add(volumenMusica);

        // Fondo entre vídeos
        var elegirFondo = Dialogos.Boton("Elegir…", Paleta.Panel);
        elegirFondo.Click += async (_, _) => await PedirFondo();
        botonQuitarFondo.Content = "Quitar";
        Dialogos.Estilo(botonQuitarFondo, Paleta.Panel);
        botonQuitarFondo.Click += (_, _) => motor.FijarFondo(null);
        var botonesFondo = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        botonesFondo.Children.Add(elegirFondo);
        botonesFondo.Children.Add(botonQuitarFondo);
        var fondo = new StackPanel { Spacing = 5, Margin = new Thickness(16, 0, 0, 0) };
        fondo.Children.Add(Dialogos.Rotulo("FONDO ENTRE VÍDEOS"));
        fondo.Children.Add(Nombre(nombreFondo));
        fondo.Children.Add(Detalle("Se ve al terminar un vídeo"));
        fondo.Children.Add(botonesFondo);

        // Salida de sonido
        salidaSonido.HorizontalAlignment = HorizontalAlignment.Stretch;
        salidaSonido.MaxWidth = 230;
        salidaSonido.FontSize = 13;
        salidaSonido.SelectionChanged += (_, _) =>
        {
            if (actualizando) return;
            var elegido = (salidaSonido.SelectedItem as ComboBoxItem)?.Tag as string;
            motor.ElegirSalidaAudio(string.IsNullOrEmpty(elegido) ? null : elegido);
        };
        var sonido = new StackPanel { Spacing = 5, Margin = new Thickness(16, 0, 0, 0) };
        sonido.Children.Add(Dialogos.Rotulo("SALIDA DE SONIDO"));
        sonido.Children.Add(salidaSonido);
        sonido.Children.Add(Detalle("Por dónde suena Proyectapp, aparte del resto del equipo"));

        var columnas = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*,*") };
        columnas.Children.Add(musica);
        Grid.SetColumn(fondo, 1);
        columnas.Children.Add(fondo);
        Grid.SetColumn(sonido, 2);
        columnas.Children.Add(sonido);

        var seccion = new StackPanel { Spacing = 10 };
        seccion.Children.Add(Dialogos.Rotulo("SALA"));
        seccion.Children.Add(columnas);
        return seccion;
    }

    /// La primera vez que se abre la app, enseña la guía de tres pasos.
    public void AyudaInicial()
    {
        if (Motor.LeerPreferencia("ayudaVista") != null) return;
        Motor.GuardarPreferencia("ayudaVista", "si");
        Dispatcher.UIThread.Post(() => Dialogos.Ayuda(this), DispatcherPriority.Background);
    }

    // =================== Salida ===================

    public async Task AlternarSalida()
    {
        if (salida == null)
        {
            AbrirSalida();
            return;
        }
        if (SalidaEnProyector && (motor.EnPantalla != null || motor.EsImagen || motor.EsVideo) && !motor.Negro)
        {
            var seguro = await Dialogos.Confirmar(this, "¿Cerrar la salida?",
                "El público dejará de ver la proyección y verá el escritorio del ordenador.", "Cerrar la salida", "Seguir proyectando");
            if (!seguro) return;
        }
        CerrarSalida();
    }

    public void AbrirSalida()
    {
        if (salida != null) return;
        var nueva = new VentanaSalida(motor, PantallaProyector());
        nueva.Closed += (_, _) =>
        {
            if (salida != nueva) return;
            salida = null;
            Plataforma.ImpedirReposo(false);
            mini?.Hide();
            Refrescar();
        };
        salida = nueva;
        nueva.Show();
        Plataforma.ImpedirReposo(true);
        Refrescar();
    }

    public void CerrarSalida()
    {
        var abierta = salida;
        if (abierta == null) return;
        motor.SoltarVideo();
        salida = null;
        abierta.Close();
        Plataforma.ImpedirReposo(false);
        mini?.Hide();
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

    private async void AlCerrar(object? sender, WindowClosingEventArgs e)
    {
        if (cierreConfirmado || salida == null)
        {
            CerrarSalida();
            mini?.Close();
            return;
        }
        e.Cancel = true;
        var seguro = await Dialogos.Confirmar(this, "¿Salir de Proyectapp?",
            "La salida está abierta: si sales, el público dejará de ver la proyección.", "Salir", "Seguir proyectando");
        if (!seguro) return;
        cierreConfirmado = true;
        Close();
    }

    // =================== Mini control flotante ===================

    private void MostrarMiniSiProcede()
    {
        if (salida == null || IsActive || salida.IsActive) return;
        if (OwnedWindows.Any(v => v.IsActive)) return;
        if (mini == null) CrearMini();
        RefrescarMini();
        mini!.Show();
    }

    public void MostrarMini()
    {
        if (mini == null) CrearMini();
        RefrescarMini();
        mini!.Show();
    }

    public void OcultarMini() => mini?.Hide();

    private void CrearMini()
    {
        miniTitulo = new TextBlock { FontSize = 12, FontWeight = FontWeight.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis };
        miniRestante = new TextBlock { FontFamily = Paleta.Mono, FontSize = 26, FontWeight = FontWeight.SemiBold };
        miniPausa = Dialogos.Boton("❚❚", Paleta.Panel, grande: true);
        miniPausa.Click += (_, _) => motor.AlternarPausa();
        miniNegro = Dialogos.Boton("NEGRO", Brushes.Black, grande: true);
        miniNegro.MinWidth = 76;
        miniNegro.Click += (_, _) => motor.AlternarNegro();
        var textos = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        textos.Children.Add(miniTitulo);
        textos.Children.Add(miniRestante);
        var botones = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        botones.Children.Add(miniPausa);
        botones.Children.Add(miniNegro);
        var fila = new DockPanel { Margin = new Thickness(12) };
        DockPanel.SetDock(botones, Dock.Right);
        fila.Children.Add(botones);
        fila.Children.Add(textos);

        var ventana = new Window
        {
            Title = "Proyectapp",
            Width = 340,
            Height = 78,
            CanResize = false,
            Topmost = true,
            ShowInTaskbar = false,
            ShowActivated = false,
            SystemDecorations = SystemDecorations.BorderOnly,
            Background = Paleta.Tinta,
            Foreground = Paleta.Papel,
            Content = fila,
            WindowStartupLocation = WindowStartupLocation.Manual,
        };
        ventana.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(ventana).Properties.IsLeftButtonPressed) ventana.BeginMoveDrag(e);
        };
        var pantalla = Screens.ScreenFromWindow(this) ?? Screens.Primary;
        if (pantalla != null)
        {
            var area = pantalla.WorkingArea;
            ventana.Position = new PixelPoint(
                area.X + area.Width - (int)(360 * pantalla.Scaling),
                area.Y + area.Height - (int)(110 * pantalla.Scaling));
        }
        ventana.Closing += (_, e) =>
        {
            if (cierreConfirmado || salida == null) return;
            e.Cancel = true;
            ventana.Hide();
        };
        mini = ventana;
    }

    private void RefrescarMini()
    {
        if (mini == null || miniTitulo == null || miniRestante == null || miniPausa == null || miniNegro == null) return;
        miniTitulo.Text = motor.Negro ? "PANTALLA EN NEGRO" : string.IsNullOrEmpty(motor.TituloEnPantalla) ? "Fondo en pantalla" : motor.TituloEnPantalla;
        miniRestante.Text = motor.EsVideo ? "-" + Formatos.Tiempo(motor.Restante) : "--:--";
        miniRestante.Foreground = motor.EsVideo && motor.Restante <= 30 ? Paleta.Ambar : Paleta.Papel;
        miniPausa.Content = motor.Reproduciendo ? "❚❚" : "▶";
        miniPausa.IsEnabled = motor.EsVideo;
        miniNegro.Content = motor.Negro ? "QUITAR" : "NEGRO";
        miniNegro.Background = motor.Negro ? Paleta.Ambar : Brushes.Black;
        miniNegro.Foreground = motor.Negro ? Paleta.Tinta : Paleta.Papel;
    }

    // =================== Acciones ===================

    /// Lanza la pieza; si hay un vídeo en marcha, pide confirmación antes de cortarlo.
    private async Task PedirLanzar(Pieza pieza, bool desdeElPrincipio = false)
    {
        if (motor.HayQueConfirmarCorte)
        {
            var misma = motor.EnPantalla == pieza;
            var seguro = await Dialogos.Confirmar(this, $"¿Cortar «{motor.TituloEnPantalla}»?",
                $"Le quedan {Formatos.Tiempo(motor.Restante)}. El público verá el corte.",
                misma ? "Volver a empezarla" : $"Cortar y lanzar «{pieza.Nombre}»", "Seguir con la actual");
            if (!seguro) return;
            if (misma) desdeElPrincipio = true;
        }
        if (desdeElPrincipio) motor.OlvidarPosicion(pieza);
        motor.Lanzar(pieza, desdeElPrincipio ? null : pieza.Posicion);
    }

    private async Task<bool> ConfirmarCorte(string accion)
    {
        if (!motor.HayQueConfirmarCorte) return true;
        return await Dialogos.Confirmar(this, $"¿Cortar «{motor.TituloEnPantalla}»?",
            $"Le quedan {Formatos.Tiempo(motor.Restante)}. El público verá el corte.", accion, "Seguir con la actual");
    }

    private async Task MostrarMensaje()
    {
        var texto = (mensaje.Text ?? "").Trim();
        if (texto.Length == 0) return;
        if (!await ConfirmarCorte("Cortar y mostrar el mensaje")) return;
        motor.MostrarMensaje(texto);
        Focus();
    }

    private async Task IniciarCuenta(int minutos)
    {
        if (!await ConfirmarCorte("Cortar y mostrar la cuenta atrás")) return;
        motor.IniciarCuenta(minutos * 60, mensaje.Text ?? "");
        Focus();
    }

    private static FilePickerFileType Tipos(string nombre, IEnumerable<string> extensiones) =>
        new(nombre) { Patterns = extensiones.Select(e => "*." + e).ToList() };

    private async Task<List<string>> Elegir(string titulo, bool varios, FilePickerFileType tipo)
    {
        var elegidos = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = titulo,
            AllowMultiple = varios,
            FileTypeFilter = new[] { tipo },
        });
        return elegidos.Select(a => a.TryGetLocalPath()).Where(r => !string.IsNullOrEmpty(r)).Select(r => r!).ToList();
    }

    private async Task PedirArchivos()
    {
        var rutas = await Elegir("Añadir vídeos e imágenes", true, Tipos("Vídeos e imágenes", Formatos.Video.Concat(Formatos.Imagen)));
        if (rutas.Count > 0) motor.Agregar(rutas);
    }

    private async Task PedirMusica()
    {
        var rutas = await Elegir("Música de espera", true, Tipos("Audio", Formatos.Audio));
        if (rutas.Count == 0) return;
        motor.FijarMusica(rutas);
        motor.EncenderMusica();
    }

    private async Task PedirFondo()
    {
        var rutas = await Elegir("Imagen de fondo entre vídeos", false, Tipos("Imágenes", Formatos.Imagen));
        if (rutas.Count > 0) motor.FijarFondo(rutas[0]);
    }

    private async Task Localizar(Pieza pieza)
    {
        var rutas = await Elegir($"Localizar «{pieza.Nombre}»", false, Tipos("Vídeos e imágenes", Formatos.Video.Concat(Formatos.Imagen)));
        if (rutas.Count > 0) motor.Relocalizar(pieza, rutas[0]);
    }

    private async Task PedirSubtitulos(Pieza pieza)
    {
        var rutas = await Elegir($"Subtítulos de «{pieza.Nombre}»", false, Tipos("Subtítulos", new[] { "srt", "ass", "ssa", "sub", "vtt" }));
        if (rutas.Count > 0) motor.FijarSubtitulos(pieza, rutas[0]);
    }

    private async Task Renombrar(Pieza pieza)
    {
        var nuevo = await Dialogos.PedirTexto(this, pieza.Tipo == TipoPieza.Texto ? "Editar el texto" : "Renombrar", pieza.Texto ?? pieza.Nombre);
        if (nuevo != null) motor.Renombrar(pieza, nuevo);
    }

    private async Task NuevaFuncion()
    {
        if (motor.Piezas.Count > 0)
        {
            var seguro = await Dialogos.Confirmar(this, "¿Empezar una función nueva?",
                "Se vaciará la lista actual. Los archivos de vídeo e imagen no se borran.", "Vaciar la lista", "Cancelar");
            if (!seguro) return;
        }
        motor.Nueva();
    }

    private async Task AbrirFuncion()
    {
        if (motor.Piezas.Count > 0)
        {
            var seguro = await Dialogos.Confirmar(this, "¿Abrir otra función?",
                "Sustituirá a la lista actual y detendrá lo que se esté proyectando.", "Abrir otra", "Cancelar");
            if (!seguro) return;
        }
        var rutas = await Elegir("Abrir función", false, Tipos("Funciones de Proyectapp", new[] { "proyectapp", "cabina", "json" }));
        if (rutas.Count > 0) motor.Abrir(rutas[0]);
    }

    private async Task GuardarFuncion()
    {
        var archivo = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Guardar función",
            SuggestedFileName = motor.Funcion.Nombre,
            DefaultExtension = "proyectapp",
            FileTypeChoices = new[] { Tipos("Función de Proyectapp", new[] { "proyectapp" }) },
        });
        var ruta = archivo?.TryGetLocalPath();
        if (!string.IsNullOrEmpty(ruta)) motor.GuardarComo(ruta);
    }

    private async Task ReunirArchivos()
    {
        if (motor.Copiando || motor.Piezas.Count == 0) return;
        var carpetas = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Elige o crea una carpeta para reunir los archivos de la función",
            AllowMultiple = false,
        });
        var ruta = carpetas.FirstOrDefault()?.TryGetLocalPath();
        if (!string.IsNullOrEmpty(ruta)) await motor.Reunir(ruta);
    }

    private void AlSoltar(object? sender, DragEventArgs e)
    {
        var archivos = e.Data.GetFiles();
        if (archivos == null) return;
        var rutas = archivos.Select(a => a.TryGetLocalPath()).Where(r => !string.IsNullOrEmpty(r)).Select(r => r!).ToList();
        if (rutas.Count > 0) motor.Agregar(rutas);
    }

    private async void AlPulsarTecla(object? sender, KeyEventArgs e)
    {
        if (FocusManager?.GetFocusedElement() is TextBox) return;
        var orden = e.KeyModifiers.HasFlag(KeyModifiers.Control) || e.KeyModifiers.HasFlag(KeyModifiers.Meta);
        var alt = e.KeyModifiers.HasFlag(KeyModifiers.Alt);
        if (e.Key == Key.Space && !orden && !alt)
        {
            if (!motor.EsVideo) return;
            e.Handled = true;
            motor.AlternarPausa();
        }
        else if (e.Key == Key.B && orden && !alt)
        {
            e.Handled = true;
            motor.AlternarNegro();
        }
        else if (e.Key == Key.Right && orden)
        {
            e.Handled = true;
            if (motor.Siguiente is { } siguiente) await PedirLanzar(siguiente);
        }
        else if (e.Key == Key.Enter && orden)
        {
            e.Handled = true;
            var elegida = motor.Piezas.FirstOrDefault(p => p.Id == motor.Seleccion);
            if (elegida != null) await PedirLanzar(elegida);
        }
    }

    // =================== Lista ===================

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
        resumen.Text = $"{(n == 1 ? "1 pieza" : n + " piezas")} · {Formatos.Tiempo(motor.DuracionTotal)} de vídeo";
        RefrescarCabeceraDeLista();
    }

    private void RefrescarCabeceraDeLista()
    {
        var quedan = motor.DuracionPorDelante;
        horaFin.IsVisible = quedan > 0;
        if (quedan > 0)
        {
            horaFin.Text = $"Quedan {Formatos.Tiempo(quedan)} · sin pausas acaba a las {DateTime.Now.AddSeconds(quedan):HH:mm}";
        }
        nota.IsVisible = !string.IsNullOrEmpty(motor.Nota);
        nota.Text = motor.Nota == null ? "" : "✓ " + motor.Nota;
        botonComprobar.Content = motor.Comprobando ? "Comprobando…" : "Comprobar";
        botonComprobar.IsEnabled = motor.Piezas.Count > 0 && !motor.Comprobando;
    }

    private Control Fila(Pieza pieza, int numero)
    {
        var enPantalla = motor.EnPantalla == pieza;
        var seleccionada = motor.Seleccion == pieza.Id;
        var falta = motor.Faltantes.Contains(pieza.Id);
        motor.Problemas.TryGetValue(pieza.Id, out var problema);
        var grave = falta || problema?.Grave == true;
        var pasada = pieza.Pasada && !enPantalla;
        var punto = pieza.Tipo == TipoPieza.Video && !enPantalla ? pieza.Posicion : null;

        var indice = new TextBlock
        {
            Text = numero.ToString("00"),
            FontFamily = Paleta.Mono,
            FontSize = 13,
            Foreground = enPantalla ? Paleta.Lima : Paleta.Tenue,
            VerticalAlignment = VerticalAlignment.Center,
            Width = 28,
        };

        // Miniatura: al pulsarla se abren los fotogramas de la pieza
        Control interior;
        if (!grave && motor.MiniaturasDeLista.TryGetValue(pieza.Id, out var miniatura))
        {
            interior = new Image { Source = miniatura, Stretch = Stretch.Uniform };
        }
        else
        {
            interior = new TextBlock
            {
                Text = grave ? "!" : pieza.Tipo == TipoPieza.Texto ? "Aa" : pieza.Tipo == TipoPieza.Video ? "▶" : "▣",
                Foreground = grave ? Paleta.Rojo : Paleta.Tenue,
                FontSize = 13,
                FontWeight = FontWeight.SemiBold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
        }
        var ver = new Button
        {
            Width = 62,
            Height = 36,
            Padding = new Thickness(0),
            Background = Brushes.Black,
            BorderBrush = Paleta.Panel,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Content = interior,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 10, 0),
        };
        ver.Click += (_, _) => Dialogos.Previa(this, motor, pieza);
        ToolTip.SetTip(ver, "Ver fotogramas de esta pieza sin proyectarla");

        var nombre = new TextBlock { Text = pieza.Nombre, FontSize = 14, FontWeight = FontWeight.Medium, TextTrimming = TextTrimming.CharacterEllipsis };
        var detalle = new TextBlock
        {
            Text = DetalleDe(pieza, enPantalla, pasada, falta, problema),
            FontFamily = Paleta.Mono,
            FontSize = 11,
            Foreground = grave ? Paleta.Rojo : enPantalla ? Paleta.Lima : Paleta.Tenue,
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        var textos = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 2 };
        textos.Children.Add(nombre);
        textos.Children.Add(detalle);

        var lanzar = Dialogos.Boton(punto is { } p ? "↪  Seguir " + Formatos.Tiempo(p) : "▶  Lanzar", enPantalla ? Paleta.Panel : Paleta.Lima, oscuro: !enPantalla);
        lanzar.IsEnabled = !falta;
        lanzar.Margin = new Thickness(8, 0, 4, 0);
        lanzar.Click += async (_, _) => await PedirLanzar(pieza);
        ToolTip.SetTip(lanzar, punto != null ? "Seguir donde se cortó. Para empezar de cero, usa el menú ···." : "Proyectar esta pieza");

        var menu = new MenuFlyout();
        if (punto != null)
        {
            menu.Items.Add(Entrada("Lanzar desde el principio", async () => await PedirLanzar(pieza, desdeElPrincipio: true), !falta));
        }
        menu.Items.Add(Entrada("Ver fotogramas", () => Dialogos.Previa(this, motor, pieza)));
        menu.Items.Add(Entrada(pieza.Tipo == TipoPieza.Texto ? "Editar el texto" : "Renombrar", async () => await Renombrar(pieza)));
        if (pieza.Tipo != TipoPieza.Texto) menu.Items.Add(Entrada("Localizar archivo…", async () => await Localizar(pieza)));
        if (pieza.Tipo == TipoPieza.Video)
        {
            menu.Items.Add(new Separator());
            menu.Items.Add(Entrada(pieza.Subtitulos == null ? "Añadir subtítulos…" : "Cambiar subtítulos…", async () => await PedirSubtitulos(pieza)));
            if (pieza.Subtitulos != null) menu.Items.Add(Entrada("Quitar subtítulos", () => motor.FijarSubtitulos(pieza, null)));
            menu.Items.Add(Entrada(pieza.Encadena == true ? "No lanzar la siguiente al terminar" : "Al terminar, lanzar sola la siguiente", () => motor.AlternarEncadenado(pieza)));
            if (enPantalla)
            {
                menu.Items.Add(Entrada("Empezar siempre desde este punto", motor.MarcarInicio));
                menu.Items.Add(Entrada("Terminar siempre en este punto", motor.MarcarFin));
            }
            if (pieza.Inicio != null || pieza.Fin != null) menu.Items.Add(Entrada("Quitar el recorte", () => motor.QuitarRecorte(pieza)));
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(Entrada("Subir", () => motor.Mover(pieza, -1), numero > 1));
        menu.Items.Add(Entrada("Bajar", () => motor.Mover(pieza, 1), numero < motor.Piezas.Count));
        menu.Items.Add(new Separator());
        menu.Items.Add(Entrada("Quitar de la lista", () => motor.Quitar(pieza)));
        var mas = Dialogos.Boton("···", Brushes.Transparent);
        mas.Flyout = menu;
        ToolTip.SetTip(mas, "Mover, renombrar, subtítulos, recorte y más");

        var rejilla = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto,Auto"), Margin = new Thickness(14, 8, 8, 8) };
        rejilla.Children.Add(indice);
        Grid.SetColumn(ver, 1);
        rejilla.Children.Add(ver);
        Grid.SetColumn(textos, 2);
        rejilla.Children.Add(textos);
        Grid.SetColumn(lanzar, 3);
        rejilla.Children.Add(lanzar);
        Grid.SetColumn(mas, 4);
        rejilla.Children.Add(mas);

        var marco = new Border
        {
            Child = rejilla,
            Background = enPantalla ? Paleta.LimaSuave : seleccionada ? Paleta.Panel : Paleta.Pizarra,
            Opacity = pasada ? 0.55 : 1,
        };
        marco.PointerPressed += (_, _) =>
        {
            if (motor.Seleccion == pieza.Id) return;
            motor.Seleccion = pieza.Id;
            RehacerLista();
        };
        return marco;
    }

    private static string DetalleDe(Pieza pieza, bool enPantalla, bool pasada, bool falta, Problema? problema)
    {
        if (falta) return "NO SE ENCUENTRA EL ARCHIVO";
        if (problema is { Grave: true }) return problema.Texto;
        string texto;
        switch (pieza.Tipo)
        {
            case TipoPieza.Video:
                texto = (pieza.Duracion is { } d ? Formatos.Tiempo(d) : "--:--") + " · " + Formatos.Extension(pieza.Ruta).ToUpperInvariant();
                if (problema != null) texto += " · " + problema.Texto;
                if (pieza.Subtitulos != null) texto += " · subt.";
                if (pieza.Inicio != null || pieza.Fin != null) texto += " · recortado";
                if (pieza.Encadena == true) texto += " · sigue sola";
                break;
            case TipoPieza.Imagen:
                texto = "Imagen fija";
                break;
            default:
                texto = "Mensaje de texto";
                break;
        }
        if (enPantalla) return "EN PANTALLA · " + texto;
        return pasada ? "Ya pasó · " + texto : texto;
    }

    // =================== Refresco ===================

    private void RefrescarMensaje()
    {
        var hayTexto = !string.IsNullOrWhiteSpace(mensaje.Text);
        botonMostrar.IsEnabled = hayTexto;
        botonALaLista.IsEnabled = hayTexto;
    }

    private void Refrescar()
    {
        actualizando = true;
        try
        {
            var abierta = salida != null;
            estadoSalida.Text = !abierta ? "SIN SALIDA" : SalidaEnProyector ? "SALIDA EN EL PROYECTOR" : "SALIDA EN VENTANA DE PRUEBA";
            estadoSalida.Foreground = abierta ? Paleta.Lima : Paleta.Tenue;
            botonSalida.Content = abierta ? "Cerrar salida" : "Abrir salida";
            Dialogos.Estilo(botonSalida, abierta ? Paleta.Panel : Paleta.Lima, oscuro: !abierta);
            avisoSalida.IsVisible = !abierta;

            if (!nombreFuncion.IsFocused && nombreFuncion.Text != motor.Funcion.Nombre) nombreFuncion.Text = motor.Funcion.Nombre;

            franjaAviso.IsVisible = !string.IsNullOrEmpty(motor.Aviso);
            textoAviso.Text = motor.Aviso ?? "";

            // Miniatura de lo que ve el público
            // En vídeo: la instantánea en vivo; si el sistema no la da, la miniatura de la pieza.
            Avalonia.Media.IImage? imagen = null;
            if (!motor.Negro)
            {
                if (!motor.EsVideo) imagen = motor.ImagenVisible;
                else if (motor.Previa != null) imagen = motor.Previa;
                else if (motor.EnPantalla != null && motor.MiniaturasDeLista.TryGetValue(motor.EnPantalla.Id, out var respaldo)) imagen = respaldo;
            }
            if (!ReferenceEquals(previa.Source, imagen)) previa.Source = imagen;
            var algo = (motor.EsVideo || motor.EsImagen) && !motor.Negro;
            marcoPrevia.BorderBrush = algo ? Paleta.Lima : Paleta.Panel;

            estado.Text = motor.Negro ? "● PANTALLA EN NEGRO"
                : motor.EsVideo ? (motor.Reproduciendo ? "▶ EN PANTALLA" : "❚❚ PAUSADO")
                : motor.EsImagen ? (motor.EsMensaje ? "■ MENSAJE EN PANTALLA" : "■ IMAGEN EN PANTALLA")
                : motor.HayFondo ? "■ FONDO EN PANTALLA" : "● PANTALLA EN NEGRO";
            estado.Foreground = algo ? Paleta.Lima : Paleta.Tenue;
            titulo.Text = string.IsNullOrEmpty(motor.TituloEnPantalla) ? "Ninguna pieza en pantalla" : motor.TituloEnPantalla;

            restante.Text = motor.EsVideo ? "-" + Formatos.Tiempo(motor.Restante) : "--:--";
            restante.Foreground = !motor.EsVideo ? Paleta.Tenue : motor.Restante <= 30 ? Paleta.Ambar : Paleta.Papel;

            barra.IsEnabled = motor.EsVideo && motor.Duracion > 0;
            barra.Maximum = Math.Max(motor.Duracion, 1);
            if (!arrastrando) barra.Value = Math.Min(Math.Max(motor.Tiempo, 0), barra.Maximum);
            transcurrido.Text = Formatos.Tiempo(motor.Tiempo);
            total.Text = Formatos.Tiempo(motor.Duracion);

            botonPausa.Content = motor.Reproduciendo ? "❚❚  Pausar" : "▶  Reanudar";
            botonPausa.IsEnabled = motor.EsVideo;
            botonFondo.IsEnabled = motor.EsVideo || motor.EsImagen;
            var nivel = Math.Clamp(motor.VolumenActual, 0, 1);
            if (Math.Abs(volumen.Value - nivel) > 0.001) volumen.Value = nivel;
            porcentaje.Text = (int)Math.Round(nivel * 100) + " %";
            ToolTip.SetTip(volumen, motor.VolumenEsDeLaPieza ? "Volumen de este vídeo: Proyectapp lo recuerda para la próxima vez" : "Volumen general");

            botonNegro.Content = motor.Negro ? "☀  QUITAR NEGRO" : "●  NEGRO";
            botonNegro.Background = motor.Negro ? Paleta.Ambar : Brushes.Black;
            botonNegro.Foreground = motor.Negro ? Paleta.Tinta : Paleta.Papel;
            botonNegro.BorderBrush = motor.Negro ? Paleta.Ambar : Paleta.Tenue;
            RefrescarMensaje();

            var siguiente = motor.Siguiente;
            nombreSiguiente.Text = siguiente?.Nombre ?? (motor.Piezas.Count == 0 ? "Añade piezas a la lista" : "Fin de la lista");
            nombreSiguiente.Foreground = siguiente != null ? Paleta.Papel : Paleta.Tenue;
            detalleSiguiente.Text = siguiente == null ? "" : siguiente.Tipo switch
            {
                TipoPieza.Video => siguiente.Duracion is { } d ? Formatos.Tiempo(d) : "--:--",
                TipoPieza.Imagen => "Imagen",
                _ => "Mensaje",
            };
            botonSiguiente.IsEnabled = siguiente != null;

            // Sala
            var canciones = motor.Funcion.Musica.Count;
            nombreMusica.Text = canciones == 0 ? "Sin música"
                : !string.IsNullOrEmpty(motor.PistaMusica) ? motor.PistaMusica
                : canciones == 1 ? "1 canción" : canciones + " canciones";
            estadoMusica.Text = !motor.MusicaEncendida ? "Apagada" : motor.EsVideo ? "Callada durante el vídeo" : "Sonando";
            estadoMusica.Foreground = motor.MusicaEncendida ? Paleta.Lima : Paleta.Tenue;
            botonMusica.Content = motor.MusicaEncendida ? "■  Parar" : "♪  Poner";
            Dialogos.Estilo(botonMusica, motor.MusicaEncendida ? Paleta.Lima : Paleta.Panel, oscuro: motor.MusicaEncendida);
            var nivelMusica = Math.Clamp(motor.Funcion.VolumenMusica, 0, 1);
            if (Math.Abs(volumenMusica.Value - nivelMusica) > 0.001) volumenMusica.Value = nivelMusica;

            nombreFondo.Text = motor.Funcion.RutaFondo == null ? "Negro" : Path.GetFileName(motor.Funcion.RutaFondo);
            botonQuitarFondo.IsVisible = motor.Funcion.RutaFondo != null;
            RefrescarSalidasDeSonido();

            RefrescarCabeceraDeLista();
            if (mini is { IsVisible: true }) RefrescarMini();
        }
        finally
        {
            actualizando = false;
        }
    }

    private string firmaDeSonido = "\0";

    private void RefrescarSalidasDeSonido()
    {
        var firma = string.Join("|", motor.Dispositivos.Select(d => d.Id + "=" + d.Nombre)) + "#" + motor.SalidaAudio;
        if (firma == firmaDeSonido) return;
        firmaDeSonido = firma;
        salidaSonido.Items.Clear();
        salidaSonido.Items.Add(new ComboBoxItem { Content = "Salida del sistema", Tag = "" });
        var elegido = 0;
        foreach (var dispositivo in motor.Dispositivos)
        {
            salidaSonido.Items.Add(new ComboBoxItem { Content = dispositivo.Nombre, Tag = dispositivo.Id });
            if (dispositivo.Id == motor.SalidaAudio) elegido = salidaSonido.Items.Count - 1;
        }
        salidaSonido.SelectedIndex = elegido;
    }
}
