using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;

namespace Proyectapp;

/// Ventanas pequeñas: confirmaciones, pedir un texto, fotogramas de una pieza y la ayuda.
public static class Dialogos
{
    public static Button Boton(string texto, IBrush fondo, bool oscuro = false, bool grande = false)
    {
        var boton = new Button { Content = texto };
        Estilo(boton, fondo, oscuro, grande);
        return boton;
    }

    public static void Estilo(Button boton, IBrush fondo, bool oscuro = false, bool grande = false)
    {
        boton.Background = fondo;
        boton.Foreground = oscuro ? Paleta.Tinta : Paleta.Papel;
        boton.FontSize = grande ? 14 : 13;
        boton.FontWeight = FontWeight.SemiBold;
        boton.Padding = grande ? new Thickness(14, 9) : new Thickness(10, 6);
        boton.CornerRadius = new CornerRadius(6);
        boton.VerticalAlignment = VerticalAlignment.Center;
    }

    public static TextBlock Rotulo(string texto) => new()
    {
        Text = texto,
        FontFamily = Paleta.Mono,
        FontSize = 11,
        FontWeight = FontWeight.SemiBold,
        Foreground = Paleta.Tenue,
    };

    public static Bitmap? Recurso(string nombre)
    {
        try
        {
            using var flujo = AssetLoader.Open(new Uri("avares://Proyectapp/Recursos/" + nombre));
            return new Bitmap(flujo);
        }
        catch
        {
            return null;
        }
    }

    private static Window Base(string titulo, double ancho)
    {
        return new Window
        {
            Title = titulo,
            Width = ancho,
            SizeToContent = SizeToContent.Height,
            CanResize = false,
            ShowInTaskbar = false,
            Background = Paleta.Pizarra,
            Foreground = Paleta.Papel,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
        };
    }

    public static async Task<bool> Confirmar(Window propietaria, string titulo, string texto, string aceptar, string cancelar)
    {
        var ventana = Base(titulo, 460);
        var si = Boton(aceptar, Paleta.Lima, oscuro: true, grande: true);
        var no = Boton(cancelar, Paleta.Panel, grande: true);
        no.IsCancel = true;
        si.Click += (_, _) => ventana.Close(true);
        no.Click += (_, _) => ventana.Close(false);
        var botones = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right };
        botones.Children.Add(no);
        botones.Children.Add(si);
        var panel = new StackPanel { Margin = new Thickness(22), Spacing = 12 };
        panel.Children.Add(new TextBlock { Text = titulo, FontSize = 17, FontWeight = FontWeight.Bold, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text = texto, FontSize = 13, Foreground = Paleta.Tenue, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(botones);
        ventana.Content = panel;
        return await ventana.ShowDialog<bool?>(propietaria) == true;
    }

    private static readonly (string Nombre, string Hex)[] ColoresDeFondo =
    {
        ("Negro", "#000000"), ("Gris carbón", "#2B2B2B"), ("Gris", "#6E6E6E"), ("Gris claro", "#BDBDBD"),
        ("Blanco", "#FFFFFF"), ("Crema", "#F1EDDF"), ("Azul noche", "#0E1A2B"), ("Azul", "#1F4E79"),
        ("Verde selva", "#10201B"), ("Verde", "#2F5D3A"), ("Lima", "#D2D25A"), ("Mostaza", "#C9A227"),
        ("Naranja", "#D2691E"), ("Rojo", "#8C1C13"), ("Burdeos", "#3A0E14"), ("Marrón", "#4A3020"),
    };

    /// Elige el color del fondo entre vídeos. Devuelve "#RRGGBB", o null si se cancela.
    public static async Task<string?> ElegirColor(Window propietaria, Color actual)
    {
        var ventana = Base("Color de fondo", 460);
        var elegido = actual;
        var muestra = new Border { Height = 64, CornerRadius = new CornerRadius(6), BorderBrush = Paleta.Panel, BorderThickness = new Thickness(1) };
        var codigo = new TextBox { FontFamily = Paleta.Mono, FontSize = 14, Width = 120, MaxLength = 7 };
        var avisoCodigo = new TextBlock { FontSize = 12, Foreground = Paleta.Tenue, VerticalAlignment = VerticalAlignment.Center };
        var escribiendo = false;

        void Fijar(Color color, bool desdeCodigo = false)
        {
            elegido = color;
            muestra.Background = new SolidColorBrush(color);
            if (!desdeCodigo)
            {
                escribiendo = true;
                codigo.Text = $"#{color.R:X2}{color.G:X2}{color.B:X2}";
                escribiendo = false;
            }
            avisoCodigo.Text = "";
        }

        var rejilla = new UniformGrid { Columns = 8 };
        foreach (var (nombre, hex) in ColoresDeFondo)
        {
            var color = Color.Parse(hex);
            var boton = new Button
            {
                Width = 44,
                Height = 34,
                Margin = new Thickness(0, 0, 6, 6),
                Background = new SolidColorBrush(color),
                BorderBrush = Paleta.Panel,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(5),
            };
            ToolTip.SetTip(boton, nombre);
            AutomationProperties.SetName(boton, nombre);
            boton.Click += (_, _) => Fijar(color);
            rejilla.Children.Add(boton);
        }

        codigo.TextChanged += (_, _) =>
        {
            if (escribiendo) return;
            var valido = Formatos.ColorValido(codigo.Text) ?? (codigo.Text?.Trim().TrimStart('#') is "000000" ? "#000000" : null);
            if (valido != null) Fijar(Color.Parse(valido), desdeCodigo: true);
            else avisoCodigo.Text = "Escribe seis cifras, por ejemplo #1F4E79";
        };
        var filaCodigo = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        filaCodigo.Children.Add(new TextBlock { Text = "Otro color:", FontSize = 13, VerticalAlignment = VerticalAlignment.Center });
        filaCodigo.Children.Add(codigo);
        filaCodigo.Children.Add(avisoCodigo);

        var si = Boton("Usar este color", Paleta.Lima, oscuro: true, grande: true);
        var no = Boton("Cancelar", Paleta.Panel, grande: true);
        si.IsDefault = true;
        no.IsCancel = true;
        si.Click += (_, _) => ventana.Close($"#{elegido.R:X2}{elegido.G:X2}{elegido.B:X2}");
        no.Click += (_, _) => ventana.Close(null);
        var botones = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right };
        botones.Children.Add(no);
        botones.Children.Add(si);

        var panel = new StackPanel { Margin = new Thickness(22), Spacing = 12 };
        panel.Children.Add(new TextBlock { Text = "Color de fondo", FontSize = 17, FontWeight = FontWeight.Bold });
        panel.Children.Add(new TextBlock
        {
            Text = "Es lo que ve el público entre vídeos. Si también hay imagen de fondo, el color rellena lo que la imagen no cubre. El botón NEGRO sigue tapando en negro.",
            FontSize = 13,
            Foreground = Paleta.Tenue,
            TextWrapping = TextWrapping.Wrap,
        });
        panel.Children.Add(muestra);
        panel.Children.Add(rejilla);
        panel.Children.Add(filaCodigo);
        panel.Children.Add(botones);
        ventana.Content = panel;
        Fijar(actual);
        return await ventana.ShowDialog<string?>(propietaria);
    }

    public static async Task<string?> PedirTexto(Window propietaria, string titulo, string valor)
    {
        var ventana = Base(titulo, 460);
        var campo = new TextBox { Text = valor, FontSize = 14, AcceptsReturn = false };
        var si = Boton("Guardar", Paleta.Lima, oscuro: true, grande: true);
        var no = Boton("Cancelar", Paleta.Panel, grande: true);
        si.IsDefault = true;
        no.IsCancel = true;
        si.Click += (_, _) => ventana.Close(campo.Text);
        no.Click += (_, _) => ventana.Close(null);
        var botones = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right };
        botones.Children.Add(no);
        botones.Children.Add(si);
        var panel = new StackPanel { Margin = new Thickness(22), Spacing = 12 };
        panel.Children.Add(new TextBlock { Text = titulo, FontSize = 17, FontWeight = FontWeight.Bold });
        panel.Children.Add(campo);
        panel.Children.Add(botones);
        ventana.Content = panel;
        ventana.Opened += (_, _) =>
        {
            campo.Focus();
            campo.SelectAll();
        };
        var resultado = await ventana.ShowDialog<string?>(propietaria);
        return string.IsNullOrWhiteSpace(resultado) ? null : resultado.Trim();
    }

    /// Fotogramas de una pieza de la lista, para revisarla sin mandarla al proyector.
    public static void Previa(Window propietaria, Motor motor, Pieza pieza)
    {
        var ventana = Base("Vista previa · " + pieza.Nombre, 1040);
        var datos = new TextBlock { Text = "Sacando fotogramas…", FontFamily = Paleta.Mono, FontSize = 12, Foreground = Paleta.Tenue };
        var tira = new WrapPanel { Orientation = Orientation.Horizontal };
        var cerrar = Boton("Cerrar", Paleta.Panel, grande: true);
        cerrar.IsCancel = true;
        cerrar.IsDefault = true;
        cerrar.HorizontalAlignment = HorizontalAlignment.Right;
        cerrar.Click += (_, _) => ventana.Close();
        var panel = new StackPanel { Margin = new Thickness(20), Spacing = 12 };
        panel.Children.Add(new TextBlock { Text = pieza.Nombre, FontSize = 18, FontWeight = FontWeight.Bold, TextTrimming = TextTrimming.CharacterEllipsis });
        panel.Children.Add(datos);
        panel.Children.Add(tira);
        panel.Children.Add(new TextBlock { Text = "Esto solo se ve en tu pantalla, no en el proyector.", FontSize = 11, Foreground = Paleta.Tenue });
        panel.Children.Add(cerrar);
        ventana.Content = panel;
        ventana.Opened += async (_, _) =>
        {
            try
            {
                var resultado = await motor.PreviaDe(pieza);
                var partes = new List<string>();
                if (!string.IsNullOrEmpty(resultado.Detalle)) partes.Add(resultado.Detalle);
                if (pieza.Tipo == TipoPieza.Video && pieza.Duracion is { } d) partes.Add(Formatos.Tiempo(d));
                datos.Text = partes.Count > 0 ? string.Join(" · ", partes) : " ";
                if (resultado.Fotogramas.Count == 0)
                {
                    tira.Children.Add(new TextBlock { Text = "No se pudo abrir este archivo para previsualizarlo.", Foreground = Paleta.Ambar, FontSize = 13 });
                    return;
                }
                var unica = resultado.Fotogramas.Count == 1;
                foreach (var (segundo, imagen) in resultado.Fotogramas)
                {
                    var celda = new StackPanel { Spacing = 4, Margin = new Thickness(0, 0, 8, 8) };
                    celda.Children.Add(new Border
                    {
                        Background = Brushes.Black,
                        CornerRadius = new CornerRadius(5),
                        ClipToBounds = true,
                        Width = unica ? 640 : 192,
                        Height = unica ? 360 : 108,
                        Child = new Image { Source = imagen, Stretch = Stretch.Uniform },
                    });
                    if (segundo is { } s)
                    {
                        celda.Children.Add(new TextBlock { Text = Formatos.Tiempo(s), FontFamily = Paleta.Mono, FontSize = 11, Foreground = Paleta.Tenue, HorizontalAlignment = HorizontalAlignment.Center });
                    }
                    tira.Children.Add(celda);
                }
            }
            catch
            {
                datos.Text = "No se pudo previsualizar esta pieza.";
            }
        };
        ventana.Show(propietaria);
    }

    public static void Ayuda(Window propietaria)
    {
        var ventana = Base("Cómo se usa Proyectapp", 700);
        var orden = Plataforma.EsMac ? "⌘" : "Ctrl+";
        var panel = new StackPanel { Margin = new Thickness(26), Spacing = 14 };
        panel.Children.Add(new TextBlock { Text = "Cómo se usa Proyectapp", FontSize = 22, FontWeight = FontWeight.Bold });

        void Paso(string numero, string titulo, string texto)
        {
            var circulo = new Border
            {
                Width = 26, Height = 26, CornerRadius = new CornerRadius(13), Background = Paleta.Lima, VerticalAlignment = VerticalAlignment.Top,
                Child = new TextBlock { Text = numero, Foreground = Paleta.Tinta, FontWeight = FontWeight.Bold, FontFamily = Paleta.Mono, FontSize = 14, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
            };
            var textos = new StackPanel { Spacing = 2, Margin = new Thickness(12, 0, 0, 0) };
            textos.Children.Add(new TextBlock { Text = titulo, FontSize = 15, FontWeight = FontWeight.SemiBold });
            textos.Children.Add(new TextBlock { Text = texto, FontSize = 13, Foreground = Paleta.Tenue, TextWrapping = TextWrapping.Wrap });
            var fila = new DockPanel();
            DockPanel.SetDock(circulo, Dock.Left);
            fila.Children.Add(circulo);
            fila.Children.Add(textos);
            panel.Children.Add(fila);
        }
        Paso("1", "Prepara la lista", "Pulsa Añadir o arrastra aquí tus vídeos e imágenes. Cámbialos de orden arrastrándolos con el ratón dentro de la lista. Puedes tocar la lista en cualquier momento, también mientras se proyecta.");
        Paso("2", "Abre la salida", "Conecta el proyector como pantalla ampliada (no duplicada) y pulsa «Abrir salida». El público verá negro, o tu imagen de fondo, hasta que lances algo.");
        Paso("3", "Lanza cada pieza", "Pulsa Lanzar en la pieza que toque. Cuando un vídeo termina, la pantalla vuelve sola al fondo. El botón NEGRO tapa la pantalla al instante sin perder el punto.");
        panel.Children.Add(new Border { Height = 1, Background = Paleta.Panel });

        var atajos = new StackPanel { Spacing = 5 };
        atajos.Children.Add(Rotulo("ATAJOS"));
        void Atajo(string tecla, string texto)
        {
            var fila = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
            fila.Children.Add(new TextBlock { Text = tecla, FontFamily = Paleta.Mono, FontSize = 12, FontWeight = FontWeight.SemiBold, Width = 92 });
            fila.Children.Add(new TextBlock { Text = texto, FontSize = 12, Foreground = Paleta.Tenue });
            atajos.Children.Add(fila);
        }
        Atajo("Espacio", "Pausar o reanudar el vídeo");
        Atajo(orden + "B", "Poner o quitar negro");
        Atajo(orden + "→", "Lanzar la siguiente pieza");
        Atajo(orden + "Intro", "Lanzar la pieza seleccionada");
        if (Plataforma.HayAtajosGlobales)
        {
            Atajo("Ctrl+Alt+B", "Negro, desde cualquier otra app");
            Atajo("Ctrl+Alt+P", "Pausa, desde cualquier otra app");
        }

        var ocultas = new StackPanel { Spacing = 7 };
        ocultas.Children.Add(Rotulo("LO QUE NO ESTÁ A LA VISTA"));
        void Oculta(string titulo, string texto)
        {
            var bloque = new StackPanel { Spacing = 1 };
            bloque.Children.Add(new TextBlock { Text = titulo, FontSize = 12, FontWeight = FontWeight.SemiBold });
            bloque.Children.Add(new TextBlock { Text = texto, FontSize = 12, Foreground = Paleta.Tenue, TextWrapping = TextWrapping.Wrap });
            ocultas.Children.Add(bloque);
        }
        Oculta("Menú ··· de cada pieza", "Encuadre propio, subir y bajar (también se puede arrastrar), subtítulos .srt, empezar o terminar siempre en un punto, lanzar sola la siguiente y lanzar desde el principio.");
        Oculta("Botón «Seguir 12:34»", "Aparece cuando un vídeo se cortó: continúa donde se quedó. Para empezarlo de cero, usa el menú ···.");
        Oculta("Miniatura de cada pieza", "Pasa el ratón por encima para recorrer el vídeo. Púlsala para ver sus fotogramas en grande, su tamaño real y su duración, sin proyectarlo.");
        Oculta("Tira de fotogramas", "Al seleccionar un vídeo aparecen seis fotogramas debajo. Pulsa uno para lanzar el vídeo desde ese punto.");
        Oculta("Botón Ajustar proyección", "Imagen de prueba, pantalla de salida, encuadre (completa, llenar o quitar las bandas del archivo), tamaño, posición y márgenes.");
        Oculta("Botón Función", "Guardar y abrir funciones, y reunir todos los archivos en una carpeta para no depender de un USB.");

        var columnas = new Grid { ColumnDefinitions = new ColumnDefinitions("*,24,*") };
        columnas.Children.Add(atajos);
        Grid.SetColumn(ocultas, 2);
        columnas.Children.Add(ocultas);
        panel.Children.Add(columnas);

        var cerrar = Boton("Entendido", Paleta.Lima, oscuro: true, grande: true);
        cerrar.IsDefault = true;
        cerrar.IsCancel = true;
        cerrar.HorizontalAlignment = HorizontalAlignment.Right;
        cerrar.Click += (_, _) => ventana.Close();
        var pie = new Grid();
        pie.Children.Add(new TextBlock { Text = "Esta guía está siempre en el botón Ayuda.", FontSize = 12, Foreground = Paleta.Tenue, VerticalAlignment = VerticalAlignment.Center });
        pie.Children.Add(cerrar);
        panel.Children.Add(pie);
        ventana.Content = panel;
        ventana.ShowDialog(propietaria);
    }
}
