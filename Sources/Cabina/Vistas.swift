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
            Image(systemName: icono)
                .frame(width: 20)
                .foregroundStyle(grave ? Paleta.rojo : Paleta.papel)

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

            Menu {
                Section("El sonido de Cabina sale por") {
                    Button {
                        motor.elegirSalidaAudio(nil)
                    } label: {
                        if motor.salidaAudio == nil {
                            Label("Salida del sistema", systemImage: "checkmark")
                        } else {
                            Text("Salida del sistema")
                        }
                    }
                    ForEach(motor.dispositivos) { dispositivo in
                        Button {
                            motor.elegirSalidaAudio(dispositivo.uid)
                        } label: {
                            if motor.salidaAudio == dispositivo.uid {
                                Label(dispositivo.nombre, systemImage: "checkmark")
                            } else {
                                Text(dispositivo.nombre)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: motor.volumenActual == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 24, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Elegir por dónde suena Cabina (altavoces de la sala, HDMI…)")
            Slider(
                value: Binding(get: { motor.volumenActual }, set: { motor.fijarVolumen($0) }),
                in: 0...1
            )
            .frame(minWidth: 70, maxWidth: 150)
            .help(motor.volumenEsDeLaPieza
                  ? "Volumen de este vídeo: Cabina lo recuerda para la próxima vez"
                  : "Volumen general")
            Text("\(Int((motor.volumenActual * 100).rounded())) %")
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
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A CONTINUACIÓN")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Paleta.tenue)
                if let siguiente = motor.siguiente {
                    Text(siguiente.nombre)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detalle(de: siguiente))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Paleta.tenue)
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("FONDO ENTRE VÍDEOS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Paleta.tenue)
                Text(nombreFondo)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Al terminar un vídeo")
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
