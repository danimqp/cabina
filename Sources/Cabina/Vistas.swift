import CabinaCore
import SwiftUI

enum Paleta {
    static let tinta = Color(red: 0x0E / 255, green: 0x14 / 255, blue: 0x17 / 255)
    static let pizarra = Color(red: 0x17 / 255, green: 0x1F / 255, blue: 0x22 / 255)
    static let panel = Color(red: 0x20 / 255, green: 0x27 / 255, blue: 0x2B / 255)
    static let papel = Color(red: 0xE6 / 255, green: 0xE3 / 255, blue: 0xD6 / 255)
    static let ambar = Color(red: 0xF0 / 255, green: 0xA3 / 255, blue: 0x33 / 255)
    static let verde = Color(red: 0x5E / 255, green: 0xBF / 255, blue: 0x8F / 255)
    static let rojo = Color(red: 0xD9 / 255, green: 0x5B / 255, blue: 0x4E / 255)
    static let tenue = papel.opacity(0.55)
}

// MARK: Ventana de control

struct VistaControl: View {
    @EnvironmentObject private var motor: Motor

    var body: some View {
        VStack(spacing: 0) {
            BarraSuperior()
            if let aviso = motor.aviso {
                FranjaAviso(texto: aviso)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ListaPiezas()
                        .frame(width: min(520, max(380, geo.size.width * 0.38)))
                    PanelControl()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Paleta.tinta)
        .foregroundStyle(Paleta.papel)
        .onAppear {
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
            if !Pruebas.activa, !UserDefaults.standard.bool(forKey: "ayudaVista") {
                motor.ayudaVisible = true
            }
        }
        .sheet(isPresented: $motor.ayudaVisible, onDismiss: {
            UserDefaults.standard.set(true, forKey: "ayudaVista")
        }) {
            VistaAyuda()
        }
        .confirmationDialog(
            "¿Cortar «\(motor.tituloEnPantalla)»?",
            isPresented: Binding(
                get: { motor.hayPendiente },
                set: { if !$0 { motor.cancelarPendiente() } }
            ),
            titleVisibility: .visible
        ) {
            Button(textoConfirmar) {
                motor.confirmarPendiente()
            }
            Button("Seguir con la actual", role: .cancel) {
                motor.cancelarPendiente()
            }
        } message: {
            Text("Le quedan \(Tiempo.texto(motor.restante)). El público verá el corte.")
        }
    }

    private var textoConfirmar: String {
        if motor.cuentaPendiente != nil { return "Cortar y mostrar la cuenta atrás" }
        if motor.mensajePendiente != nil { return "Cortar y mostrar el mensaje" }
        if motor.pendiente == motor.idEnPantalla { return "Volver a empezarla" }
        return "Cortar y lanzar «\(motor.nombrePendiente)»"
    }
}

struct BarraSuperior: View {
    @EnvironmentObject private var motor: Motor
    @EnvironmentObject private var salida: Salida

    var body: some View {
        HStack(spacing: 16) {
            Text("CABINA")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .kerning(2)
            TextField("Nombre de la función", text: $motor.funcion.nombre)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Paleta.tenue)
                .frame(maxWidth: 340)
                .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
            Spacer()
            Button {
                motor.ayudaVisible = true
            } label: {
                Label("Ayuda", systemImage: "questionmark.circle")
            }
            .buttonStyle(BotonCabina(color: Paleta.panel))
            .fixedSize()
            .help("Cómo se usa, atajos de teclado y funciones menos visibles")
            HStack(spacing: 7) {
                Image(systemName: salida.abierta ? "dot.radiowaves.left.and.right" : "rectangle.slash")
                Text(estadoSalida)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(salida.abierta ? Paleta.verde : Paleta.tenue)
            Button(salida.abierta ? "Cerrar salida" : "Abrir salida") {
                salida.alternar()
            }
            .buttonStyle(BotonCabina(color: salida.abierta ? Paleta.panel : Paleta.verde, oscuro: !salida.abierta))
            .help("Abre la pantalla del público en el proyector")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Paleta.tinta)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Paleta.panel).frame(height: 1)
        }
    }

    private var estadoSalida: String {
        if !salida.abierta { return "SIN SALIDA" }
        return salida.enProyector ? "SALIDA EN EL PROYECTOR" : "SALIDA EN VENTANA DE PRUEBA"
    }
}

struct FranjaAviso: View {
    @EnvironmentObject private var motor: Motor
    let texto: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(texto)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Entendido") { motor.aviso = nil }
                .buttonStyle(BotonCabina(color: Paleta.tinta.opacity(0.25), oscuro: true))
        }
        .foregroundStyle(Paleta.tinta)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Paleta.ambar)
    }
}

// MARK: Lista

struct ListaPiezas: View {
    @EnvironmentObject private var motor: Motor
    @State private var editando: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ORDEN DE LA FUNCIÓN")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Paleta.tenue)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        motor.comprobar(avisar: true)
                    } label: {
                        Label(motor.comprobando ? "Comprobando…" : "Comprobar", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(BotonCabina(color: Paleta.panel))
                    .fixedSize()
                    .disabled(motor.funcion.piezas.isEmpty || motor.comprobando)
                    .help("Abre cada archivo y avisa de los que no se van a poder proyectar")
                    Button {
                        motor.pedirArchivos()
                    } label: {
                        Label("Añadir", systemImage: "plus")
                    }
                    .buttonStyle(BotonCabina(color: Paleta.panel))
                    .fixedSize()
                }
                Text(resumen)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                if motor.duracionPorDelante > 0 {
                    TimelineView(.periodic(from: .now, by: 20)) { contexto in
                        Text(textoFin(contexto.date))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Paleta.tenue)
                            .lineLimit(1)
                    }
                }
                if let nota = motor.nota {
                    Label(nota, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Paleta.verde)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if motor.funcion.piezas.isEmpty {
                vacio
            } else {
                lista
            }
        }
        .background(Paleta.pizarra)
        .dropDestination(for: URL.self) { urls, _ in
            motor.agregar(urls) > 0
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { Creditos() }
    }

    private var resumen: String {
        let n = motor.funcion.piezas.count
        let piezas = n == 1 ? "1 pieza" : "\(n) piezas"
        return "\(piezas) · \(Tiempo.texto(motor.funcion.duracionTotal)) de vídeo"
    }

    private func textoFin(_ ahora: Date) -> String {
        let quedan = motor.duracionPorDelante
        let fin = ahora.addingTimeInterval(quedan).formatted(date: .omitted, time: .shortened)
        return "Quedan \(Tiempo.texto(quedan)) · sin pausas acaba a las \(fin)"
    }

    private var vacio: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundStyle(Paleta.tenue)
            Text("La lista está vacía")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("Añade tus vídeos e imágenes, o arrástralos aquí desde el Finder. Después los ordenas arrastrando.")
                .font(.system(size: 13))
                .foregroundStyle(Paleta.tenue)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button {
                motor.pedirArchivos()
            } label: {
                Label("Añadir archivos", systemImage: "plus")
            }
            .buttonStyle(BotonCabina(color: Paleta.ambar, oscuro: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var lista: some View {
        List(selection: $motor.seleccion) {
            ForEach(Array(motor.funcion.piezas.enumerated()), id: \.element.id) { indice, pieza in
                FilaPieza(numero: indice + 1, pieza: pieza, editando: $editando)
                    .tag(pieza.id)
                    .listRowBackground(fondo(de: pieza))
                    .listRowSeparatorTint(Paleta.panel)
            }
            .onMove { origen, destino in
                motor.funcion.mover(desde: origen, a: destino)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onDeleteCommand {
            if let id = motor.seleccion, editando == nil { motor.quitar(id) }
        }
    }

    private func fondo(de pieza: Pieza) -> Color {
        if motor.idEnPantalla == pieza.id { return Paleta.ambar.opacity(0.22) }
        if motor.seleccion == pieza.id { return Paleta.panel }
        return Paleta.pizarra
    }
}

struct FilaPieza: View {
    @EnvironmentObject private var motor: Motor
    let numero: Int
    let pieza: Pieza
    @Binding var editando: UUID?
    @State private var borrador = ""
    @FocusState private var conFoco: Bool
    @State private var verPrevia = false

    /// Miniatura de la pieza; al pulsarla se abren sus fotogramas.
    private var miniatura: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.black)
            if let imagen = motor.miniaturas[pieza.id], !grave {
                Image(nsImage: imagen)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                Image(systemName: icono)
                    .foregroundStyle(grave ? Paleta.rojo : Paleta.tenue)
            }
        }
        .frame(width: 60, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Paleta.panel, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var enPantalla: Bool { motor.idEnPantalla == pieza.id }
    private var falta: Bool { motor.faltantes.contains(pieza.id) }
    private var pasada: Bool { motor.pasadas.contains(pieza.id) && !enPantalla }
    private var problema: Problema? { motor.problemas[pieza.id] }
    private var grave: Bool { falta || problema?.grave == true }
    /// Punto guardado desde el que se puede seguir un vídeo cortado.
    private var puntoGuardado: Double? {
        guard pieza.tipo == .video, !enPantalla else { return nil }
        return pieza.posicion
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", numero))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(enPantalla ? Paleta.ambar : Paleta.tenue)
            Button {
                verPrevia = true
            } label: {
                miniatura
            }
            .buttonStyle(.plain)
            .help("Ver fotogramas de esta pieza sin proyectarla")
            .popover(isPresented: $verPrevia, arrowEdge: .trailing) {
                VistaPreviaPieza(pieza: pieza)
                    .environmentObject(motor)
            }

            VStack(alignment: .leading, spacing: 3) {
                if editando == pieza.id {
                    TextField("Nombre", text: $borrador)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .focused($conFoco)
                        .onSubmit {
                            motor.renombrar(pieza.id, borrador)
                            editando = nil
                        }
                        .onExitCommand { editando = nil }
                        .onAppear {
                            borrador = pieza.nombre
                            conFoco = true
                        }
                } else {
                    Text(pieza.nombre)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(detalle)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(grave ? Paleta.rojo : (enPantalla ? Paleta.ambar : Paleta.tenue))
            }

            Spacer(minLength: 6)

            Button {
                motor.pedirLanzar(pieza.id)
            } label: {
                if let punto = puntoGuardado {
                    Label("Seguir \(Tiempo.texto(punto))", systemImage: "arrow.uturn.right")
                } else {
                    Label("Lanzar", systemImage: "play.fill")
                }
            }
            .buttonStyle(BotonCabina(color: enPantalla ? Paleta.panel : Paleta.ambar, oscuro: !enPantalla))
            .fixedSize()
            .disabled(falta)
            .help(ayudaLanzar)

            Menu {
                acciones
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Renombrar, localizar o quitar")
        }
        .padding(.vertical, 6)
        .opacity(pasada ? 0.5 : 1)
        .contextMenu { acciones }
    }

    @ViewBuilder
    private var acciones: some View {
        if let punto = puntoGuardado {
            Button("Seguir desde \(Tiempo.texto(punto))") { motor.pedirLanzar(pieza.id) }
                .disabled(falta)
            Button("Lanzar desde el principio") { motor.pedirLanzar(pieza.id, desdeElPrincipio: true) }
                .disabled(falta)
        } else {
            Button("Lanzar") { motor.pedirLanzar(pieza.id) }
                .disabled(falta)
        }
        Button("Ver fotogramas") { verPrevia = true }
        Button(pieza.tipo == .texto ? "Editar el texto" : "Renombrar") { editando = pieza.id }
        if pieza.tipo != .texto {
            Button("Localizar archivo…") { motor.localizar(pieza.id) }
        }
        if pieza.tipo == .video {
            Divider()
            if pieza.subtitulos == nil {
                Button("Añadir subtítulos (.srt)…") { motor.pedirSubtitulos(pieza.id) }
            } else {
                Button("Cambiar subtítulos…") { motor.pedirSubtitulos(pieza.id) }
                Button("Quitar subtítulos") { motor.quitarSubtitulos(pieza.id) }
            }
            Button(pieza.encadena == true ? "No lanzar la siguiente al terminar" : "Al terminar, lanzar sola la siguiente") {
                motor.alternarEncadenado(pieza.id)
            }
            if enPantalla {
                Button("Empezar siempre desde este punto") { motor.marcarInicio() }
                Button("Terminar siempre en este punto") { motor.marcarFin() }
            }
            if pieza.inicio != nil || pieza.fin != nil {
                Button("Quitar el recorte") { motor.quitarRecorte(pieza.id) }
            }
        }
        Divider()
        Button("Quitar de la lista", role: .destructive) { motor.quitar(pieza.id) }
    }

    private var icono: String {
        if grave { return "exclamationmark.triangle.fill" }
        switch pieza.tipo {
        case .video: return "film"
        case .imagen: return "photo"
        case .texto: return "textformat"
        }
    }

    private var ayudaLanzar: String {
        if puntoGuardado != nil {
            return "Seguir donde se cortó. Para empezar de cero, usa el menú de la pieza."
        }
        switch pieza.tipo {
        case .video: return "Proyectar este vídeo desde el principio"
        case .imagen: return "Mostrar esta imagen en el proyector"
        case .texto: return "Mostrar este mensaje en el proyector"
        }
    }

    private var detalle: String {
        if falta { return "NO SE ENCUENTRA EL ARCHIVO" }
        if let problema, problema.grave { return problema.texto }
        var base: String
        switch pieza.tipo {
        case .video:
            base = pieza.duracion.map { Tiempo.texto($0) } ?? "--:--"
            if let problema { base += " · " + problema.texto }
            if pieza.subtitulos != nil { base += " · subt." }
            if pieza.inicio != nil || pieza.fin != nil { base += " · recortado" }
            if pieza.encadena == true { base += " · sigue sola" }
        case .imagen:
            base = "Imagen fija"
        case .texto:
            base = "Mensaje de texto"
        }
        if enPantalla { return "EN PANTALLA · " + base }
        if pasada { return "Ya pasó · " + base }
        return base
    }
}

// MARK: Panel de control

struct PanelControl: View {
    @EnvironmentObject private var motor: Motor
    @EnvironmentObject private var salida: Salida
    @State private var arrastre: Double?
    @State private var mensaje = ""
    @AppStorage("salaAbierta") private var salaAbierta = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                previa
                    .frame(minWidth: 280, maxWidth: 560)
                    .layoutPriority(1)
                VStack(alignment: .leading, spacing: 10) {
                    estado
                    cuenta
                }
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            }
            tiempos
            transporte
            botonNegro
            mensajeRapido
            Rectangle().fill(Paleta.panel).frame(height: 1)
            pie
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Miniatura de la salida
    private var previa: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LO QUE VE EL PÚBLICO")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Paleta.tenue)
                Spacer()
            }
            VistaPrevia(motor: motor)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(bordePrevia, lineWidth: 2)
                )
            if !salida.abierta {
                Label("Salida cerrada: el público aún no ve nada", systemImage: "rectangle.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.ambar)
                    .lineLimit(1)
            }
        }
    }

    private var bordePrevia: Color {
        if motor.negro { return Paleta.panel }
        return motor.idEnPantalla != nil ? Paleta.ambar : Paleta.panel
    }

    private var estado: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(textoEstado, systemImage: iconoEstado)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(motor.idEnPantalla != nil && !motor.negro ? Paleta.ambar : Paleta.tenue)
            Text(motor.tituloEnPantalla.isEmpty ? "Ninguna pieza en pantalla" : motor.tituloEnPantalla)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var textoEstado: String {
        if motor.negro { return "PANTALLA EN NEGRO" }
        if motor.esVideo { return motor.reproduciendo ? "EN PANTALLA" : "PAUSADO" }
        if motor.esImagen { return motor.esMensaje ? "MENSAJE EN PANTALLA" : "IMAGEN EN PANTALLA" }
        return motor.hayFondo ? "FONDO EN PANTALLA" : "PANTALLA EN NEGRO"
    }

    private var iconoEstado: String {
        if motor.negro { return "moon.fill" }
        if motor.esVideo { return motor.reproduciendo ? "play.fill" : "pause.fill" }
        if motor.esImagen { return motor.esMensaje ? "text.bubble.fill" : "photo.fill" }
        return motor.hayFondo ? "photo" : "moon.fill"
    }

    // Cuenta atrás
    private var cuenta: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RESTANTE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Paleta.tenue)
            Text(motor.esVideo ? "-" + Tiempo.texto(motor.restante) : "--:--")
                .font(.system(size: 64, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(colorCuenta)
        }
    }

    // Barra de tiempo
    private var tiempos: some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(
                value: Binding(
                    get: { arrastre ?? motor.tiempo },
                    set: { arrastre = $0 }
                ),
                in: 0...max(motor.duracion, 1),
                onEditingChanged: { arrastrando in
                    if !arrastrando, let destino = arrastre {
                        motor.buscar(destino)
                        arrastre = nil
                    }
                }
            )
            .disabled(!motor.esVideo)
            HStack {
                Text(Tiempo.texto(arrastre ?? motor.tiempo))
                Spacer()
                Text(Tiempo.texto(motor.duracion))
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Paleta.tenue)
        }
    }

    private var colorCuenta: Color {
        guard motor.esVideo else { return Paleta.tenue }
        return motor.restante <= 30 ? Paleta.ambar : Paleta.papel
    }

    private var transporte: some View {
        HStack(spacing: 10) {
            Button {
                motor.alternarReproduccion()
            } label: {
                Label(motor.reproduciendo ? "Pausar" : "Reanudar",
                      systemImage: motor.reproduciendo ? "pause.fill" : "play.fill")
                    .frame(minWidth: 96)
            }
            .buttonStyle(BotonCabina(color: Paleta.panel, grande: true))
            .fixedSize()
            .disabled(!motor.esVideo)
            .help("Barra espaciadora")

            Button {
                motor.volverAlFondo()
            } label: {
                Label("Volver al fondo", systemImage: "stop.fill")
            }
            .buttonStyle(BotonCabina(color: Paleta.panel, grande: true))
            .fixedSize()
            .disabled(motor.idEnPantalla == nil)
            .help("Retira la pieza y deja la imagen de fondo")

            Spacer()

            Image(systemName: motor.volumenActual == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(Paleta.tenue)
                .frame(width: 24)
            Slider(
                value: Binding(get: { motor.volumenActual }, set: { motor.fijarVolumen($0) }),
                in: 0...1
            )
            .frame(minWidth: 70, maxWidth: 150)
            .help(motor.volumenEsDeLaPieza
                  ? "Volumen de este vídeo: Cabina lo recuerda para la próxima vez"
                  : "Volumen general")
            Text("\(Int((max(0, min(1, motor.volumenActual)) * 100).rounded())) %")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Paleta.tenue)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private var botonNegro: some View {
        Button {
            motor.alternarNegro()
        } label: {
            HStack {
                Image(systemName: motor.negro ? "sun.max.fill" : "moon.fill")
                Text(motor.negro ? "QUITAR NEGRO" : "NEGRO")
                Spacer()
                Text("⌘B")
                    .font(.system(size: 13, design: .monospaced))
                    .opacity(0.7)
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BotonNegro(activo: motor.negro))
        .help("Tapa la pantalla al instante sin perder el punto del vídeo. Desde cualquier otra app: ⌃⌥⌘B")
    }

    // Mensaje de texto escrito al momento
    private var mensajeRapido: some View {
        let vacio = mensaje.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(Paleta.tenue)
            TextField("Mensaje rápido: «Hoy, conversatorio»", text: $mensaje)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit { mostrarMensaje() }
            Button("Mostrar") { mostrarMensaje() }
                .buttonStyle(BotonCabina(color: Paleta.ambar, oscuro: true))
                .fixedSize()
                .disabled(vacio)
                .help("Muestra el texto en el proyector, en grande sobre negro")
            Menu {
                Section("Cuenta atrás en pantalla") {
                    ForEach([1, 3, 5, 10, 15, 20, 30], id: \.self) { minutos in
                        Button(minutos == 1 ? "1 minuto" : "\(minutos) minutos") {
                            motor.pedirCuenta(minutos: minutos, titulo: mensaje)
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                    }
                }
            } label: {
                Label("Cuenta atrás", systemImage: "timer")
                    .font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Muestra una cuenta atrás. Si has escrito un texto, sale encima («Volvemos en»); si no, «Empezamos en».")
            Button {
                motor.agregarMensaje(mensaje)
                mensaje = ""
            } label: {
                Label("A la lista", systemImage: "plus")
            }
            .buttonStyle(BotonCabina(color: Paleta.tinta))
            .fixedSize()
            .disabled(vacio)
            .help("Guarda el mensaje como pieza de la lista para usarlo más tarde")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Paleta.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func mostrarMensaje() {
        motor.pedirMensaje(mensaje)
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var pie: some View {
        VStack(alignment: .leading, spacing: 12) {
            continuacion
            Rectangle().fill(Paleta.panel).frame(height: 1)
            sala
        }
    }

    // Lo siguiente de la lista, siempre a la vista
    private var continuacion: some View {
        HStack(spacing: 12) {
            Text("A CONTINUACIÓN")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Paleta.tenue)
                .fixedSize()
            if let siguiente = motor.siguiente {
                Text(siguiente.nombre)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detalle(de: siguiente))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Paleta.tenue)
                    .fixedSize()
                Spacer(minLength: 8)
                Button {
                    motor.lanzarSiguiente()
                } label: {
                    Label("Lanzarla", systemImage: "forward.end.fill")
                }
                .buttonStyle(BotonCabina(color: Paleta.panel))
                .fixedSize()
                .help("Lanzar la siguiente pieza de la lista (⌘→)")
            } else {
                Text(motor.funcion.piezas.isEmpty ? "Añade piezas a la lista" : "Fin de la lista")
                    .font(.system(size: 15))
                    .foregroundStyle(Paleta.tenue)
                Spacer()
            }
        }
    }

    // Ajustes de la sala: se preparan antes de la función y luego se pliegan
    private var sala: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { salaAbierta.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: salaAbierta ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)
                    Text("SALA")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    if !salaAbierta {
                        Text(resumenSala)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    if !salaAbierta {
                        Text("Música, fondo y sonido")
                            .font(.system(size: 11))
                            .fixedSize()
                    }
                }
                .foregroundStyle(Paleta.tenue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Música de espera, fondo entre vídeos y salida de sonido")

            if salaAbierta {
                HStack(alignment: .top, spacing: 18) {
                    columnaMusica
                    columnaFondo
                    columnaSonido
                }
            }
        }
    }

    private var resumenSala: String {
        let musica = motor.musicaEncendida ? (motor.esVideo ? "música callada" : "música sonando") : "música apagada"
        let fondo = motor.funcion.rutaFondo == nil ? "fondo negro" : "fondo con imagen"
        return "\(musica) · \(fondo) · \(nombreSalidaAudio)"
    }

    private var nombreSalidaAudio: String {
        guard let uid = motor.salidaAudio else { return "sonido del sistema" }
        return motor.dispositivos.first { $0.uid == uid }?.nombre ?? "sonido del sistema"
    }

    private var columnaMusica: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MÚSICA DE ESPERA")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Paleta.tenue)
            Text(nombreMusica)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(estadoMusica)
                .font(.system(size: 12))
                .foregroundStyle(motor.musicaEncendida ? Paleta.ambar : Paleta.tenue)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button {
                    motor.alternarMusica()
                } label: {
                    Label(motor.musicaEncendida ? "Parar" : "Poner",
                          systemImage: motor.musicaEncendida ? "stop.fill" : "music.note")
                }
                .buttonStyle(BotonCabina(color: motor.musicaEncendida ? Paleta.ambar : Paleta.panel,
                                         oscuro: motor.musicaEncendida))
                .fixedSize()
                Button("Elegir…") { motor.pedirMusica() }
                    .buttonStyle(BotonCabina(color: Paleta.panel))
                    .fixedSize()
            }
            Slider(value: $motor.funcion.volumenMusica, in: 0...1)
                .frame(maxWidth: 150)
                .help("Volumen de la música de espera")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var columnaFondo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FONDO ENTRE VÍDEOS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Paleta.tenue)
            Text(nombreFondo)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Se ve al terminar un vídeo")
                .font(.system(size: 12))
                .foregroundStyle(Paleta.tenue)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button("Elegir…") { motor.pedirFondo() }
                    .buttonStyle(BotonCabina(color: Paleta.panel))
                    .fixedSize()
                if motor.funcion.rutaFondo != nil {
                    Button("Quitar") { motor.quitarFondo() }
                        .buttonStyle(BotonCabina(color: Paleta.panel))
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var columnaSonido: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SALIDA DE SONIDO")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Paleta.tenue)
            Picker("Salida de sonido", selection: Binding(
                get: { motor.salidaAudio ?? "" },
                set: { motor.elegirSalidaAudio($0.isEmpty ? nil : $0) }
            )) {
                Text("Salida del sistema").tag("")
                ForEach(motor.dispositivos) { dispositivo in
                    Text(dispositivo.nombre).tag(dispositivo.uid)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 190)
            Text("Por dónde suena Cabina, aparte del resto del Mac")
                .font(.system(size: 12))
                .foregroundStyle(Paleta.tenue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detalle(de pieza: Pieza) -> String {
        switch pieza.tipo {
        case .video: return pieza.duracion.map { Tiempo.texto($0) } ?? "--:--"
        case .imagen: return "Imagen"
        case .texto: return "Mensaje"
        }
    }

    private var nombreMusica: String {
        let n = motor.funcion.musica.count
        if n == 0 { return "Sin música" }
        if !motor.pistaMusica.isEmpty { return motor.pistaMusica }
        return n == 1 ? "1 canción" : "\(n) canciones"
    }

    private var estadoMusica: String {
        if !motor.musicaEncendida { return "Apagada" }
        return motor.esVideo ? "Callada durante el vídeo" : "Sonando"
    }

    private var nombreFondo: String {
        guard let ruta = motor.funcion.rutaFondo else { return "Negro" }
        return URL(fileURLWithPath: ruta).lastPathComponent
    }
}

// MARK: Previsualización de una pieza

/// Fotogramas de una pieza de la lista, para revisarla sin mandarla al proyector.
struct VistaPreviaPieza: View {
    @EnvironmentObject private var motor: Motor
    let pieza: Pieza
    @State private var fotogramas: [Fotograma] = []
    @State private var detalle = ""
    @State private var cargando = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pieza.nombre)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(lineaDeDatos)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Paleta.tenue)

            if cargando {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Sacando fotogramas…")
                        .font(.system(size: 12))
                        .foregroundStyle(Paleta.tenue)
                }
                .frame(width: 520, height: 120)
            } else if fotogramas.isEmpty {
                Label("No se pudo abrir este archivo para previsualizarlo.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Paleta.ambar)
                    .frame(width: 520, alignment: .leading)
            } else if fotogramas.count == 1, let unica = fotogramas.first {
                Image(nsImage: unica.imagen)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 520, maxHeight: 300)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(fotogramas) { fotograma in
                        VStack(spacing: 4) {
                            Image(nsImage: fotograma.imagen)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 190, height: 107)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            Text(Tiempo.texto(fotograma.segundo ?? 0))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Paleta.tenue)
                        }
                    }
                }
            }
            Text("Esto solo se ve en tu pantalla, no en el proyector.")
                .font(.system(size: 11))
                .foregroundStyle(Paleta.tenue)
        }
        .padding(16)
        .background(Paleta.pizarra)
        .foregroundStyle(Paleta.papel)
        .preferredColorScheme(.dark)
        .task {
            let resultado = await motor.previa(de: pieza)
            fotogramas = resultado.fotogramas
            detalle = resultado.detalle
            cargando = false
        }
    }

    private var lineaDeDatos: String {
        var partes: [String] = []
        if !detalle.isEmpty { partes.append(detalle) }
        if pieza.tipo == .video, let duracion = pieza.duracion { partes.append(Tiempo.texto(duracion)) }
        return partes.isEmpty ? " " : partes.joined(separator: " · ")
    }
}

// MARK: Ayuda

/// Guía de tres pasos, atajos y funciones que no están a simple vista.
struct VistaAyuda: View {
    @Environment(\.dismiss) private var cerrar

    private let pasos: [(String, String, String)] = [
        ("1", "Prepara la lista",
         "Pulsa Añadir o arrastra aquí tus vídeos e imágenes. Ordénalos arrastrando. Puedes cambiar la lista en cualquier momento, también mientras se proyecta."),
        ("2", "Abre la salida",
         "Conecta el proyector como pantalla ampliada (no duplicada) y pulsa «Abrir salida». El público verá negro, o tu imagen de fondo, hasta que lances algo."),
        ("3", "Lanza cada pieza",
         "Pulsa Lanzar en la pieza que toque. Cuando un vídeo termina, la pantalla vuelve sola al fondo. El botón NEGRO tapa la pantalla al instante sin perder el punto."),
    ]

    private let atajos: [(String, String)] = [
        ("Espacio", "Pausar o reanudar el vídeo"),
        ("⌘B", "Poner o quitar negro"),
        ("⌘→", "Lanzar la siguiente pieza"),
        ("⌘↩", "Lanzar la pieza seleccionada"),
        ("⇧⌘P", "Abrir o cerrar la salida"),
        ("⌘I", "Añadir archivos"),
        ("⌃⌥⌘B", "Negro, desde cualquier otra app"),
        ("⌃⌥⌘P", "Pausa, desde cualquier otra app"),
    ]

    private let ocultas: [(String, String)] = [
        ("Menú ⋯ de cada pieza", "Subtítulos .srt, empezar o terminar siempre en un punto, lanzar sola la siguiente y lanzar desde el principio."),
        ("Botón «Seguir 12:34»", "Aparece cuando un vídeo se cortó: continúa donde se quedó. Para empezarlo de cero, usa el menú ⋯."),
        ("Miniatura de cada pieza", "Púlsala para ver cinco fotogramas del vídeo, su tamaño real y su duración, sin proyectarlo."),
        ("Sección Sala", "Música de espera, imagen de fondo entre vídeos y por dónde sale el sonido."),
        ("Menú Archivo", "Guardar y abrir funciones, y reunir todos los archivos en una carpeta para no depender de un USB."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cómo se usa Cabina")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(pasos, id: \.0) { paso in
                    HStack(alignment: .top, spacing: 12) {
                        Text(paso.0)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Paleta.tinta)
                            .frame(width: 26, height: 26)
                            .background(Paleta.ambar, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paso.1)
                                .font(.system(size: 15, weight: .semibold))
                            Text(paso.2)
                                .font(.system(size: 13))
                                .foregroundStyle(Paleta.tenue)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Rectangle().fill(Paleta.panel).frame(height: 1)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ATAJOS")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Paleta.tenue)
                    ForEach(atajos, id: \.0) { atajo in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(atajo.0)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(width: 64, alignment: .leading)
                            Text(atajo.1)
                                .font(.system(size: 12))
                                .foregroundStyle(Paleta.tenue)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("LO QUE NO ESTÁ A LA VISTA")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Paleta.tenue)
                    ForEach(ocultas, id: \.0) { fila in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fila.0)
                                .font(.system(size: 12, weight: .semibold))
                            Text(fila.1)
                                .font(.system(size: 12))
                                .foregroundStyle(Paleta.tenue)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Esta guía está siempre en el botón Ayuda.")
                    .font(.system(size: 12))
                    .foregroundStyle(Paleta.tenue)
                Spacer()
                Button("Entendido") { cerrar() }
                    .buttonStyle(BotonCabina(color: Paleta.ambar, oscuro: true, grande: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 660)
        .background(Paleta.tinta)
        .foregroundStyle(Paleta.papel)
        .preferredColorScheme(.dark)
    }
}

// MARK: Créditos

enum Marca {
    static let logo: NSImage? = Bundle.main.url(forResource: "muyuna", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }
    static let web = URL(string: "https://muyuna.org")
}

/// Pie de la lista: logo de Muyuna y autoría.
struct Creditos: View {
    var body: some View {
        HStack(spacing: 12) {
            if let logo = Marca.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 46)
                    .accessibilityLabel("Muyuna")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("App desarrollada por")
                    .font(.system(size: 11))
                    .foregroundStyle(Paleta.tenue)
                if let web = Marca.web {
                    Link("Muyuna.org", destination: web)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Paleta.papel)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Paleta.pizarra)
        .overlay(alignment: .top) {
            Rectangle().fill(Paleta.panel).frame(height: 1)
        }
    }
}

/// Control mínimo que flota sobre las demás apps mientras se proyecta.
struct VistaMini: View {
    @EnvironmentObject private var motor: Motor

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(motor.negro ? "PANTALLA EN NEGRO" : (motor.tituloEnPantalla.isEmpty ? "Fondo en pantalla" : motor.tituloEnPantalla))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(motor.esVideo ? "-" + Tiempo.texto(motor.restante) : "--:--")
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(motor.esVideo && motor.restante <= 30 ? Paleta.ambar : Paleta.papel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                motor.alternarReproduccion()
            } label: {
                Image(systemName: motor.reproduciendo ? "pause.fill" : "play.fill")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(BotonCabina(color: Paleta.panel, grande: true))
            .disabled(!motor.esVideo)
            .help("Pausar o reanudar")
            Button {
                motor.alternarNegro()
            } label: {
                Text(motor.negro ? "QUITAR" : "NEGRO")
                    .frame(minWidth: 58)
            }
            .buttonStyle(BotonCabina(color: motor.negro ? Paleta.ambar : Color.black, oscuro: motor.negro, grande: true))
            .help("Poner o quitar negro")
        }
        .padding(12)
        .frame(width: 330)
        .background(Paleta.tinta)
        .foregroundStyle(Paleta.papel)
        .preferredColorScheme(.dark)
    }
}

// MARK: Botones

struct BotonCabina: ButtonStyle {
    var color: Color
    var oscuro = false
    var grande = false
    @Environment(\.isEnabled) private var habilitado

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: grande ? 14 : 13, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(oscuro ? Paleta.tinta : Paleta.papel)
            .padding(.horizontal, grande ? 14 : 10)
            .padding(.vertical, grande ? 9 : 6)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
            .opacity(habilitado ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(Rectangle())
    }
}

struct BotonNegro: ButtonStyle {
    var activo: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(activo ? Paleta.tinta : Paleta.papel)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(activo ? Paleta.ambar : Color.black, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(activo ? Paleta.ambar : Paleta.papel.opacity(0.45), lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}
