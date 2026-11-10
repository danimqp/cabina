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
                get: { motor.pendiente != nil },
                set: { if !$0 { motor.pendiente = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(motor.pendiente == motor.idEnPantalla
                   ? "Volver a empezarla"
                   : "Cortar y lanzar «\(motor.funcion.pieza(motor.pendiente)?.nombre ?? "")»") {
                motor.confirmarPendiente()
            }
            Button("Seguir con la actual", role: .cancel) {
                motor.pendiente = nil
            }
        } message: {
            Text("Le quedan \(Tiempo.texto(motor.restante)). El público verá el corte.")
        }
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ORDEN DE LA FUNCIÓN")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Paleta.tenue)
                    Text(resumen)
                        .font(.system(size: 13, design: .monospaced))
                }
                Spacer()
                Button {
                    motor.pedirArchivos()
                } label: {
                    Label("Añadir", systemImage: "plus")
                }
                .buttonStyle(BotonCabina(color: Paleta.panel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

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
    }

    private var resumen: String {
        let n = motor.funcion.piezas.count
        let piezas = n == 1 ? "1 pieza" : "\(n) piezas"
        return "\(piezas) · \(Tiempo.texto(motor.funcion.duracionTotal)) de vídeo"
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

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", numero))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(enPantalla ? Paleta.ambar : Paleta.tenue)
            Image(systemName: icono)
                .frame(width: 20)
                .foregroundStyle(falta ? Paleta.rojo : Paleta.papel)

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
                    .foregroundStyle(falta ? Paleta.rojo : (enPantalla ? Paleta.ambar : Paleta.tenue))
            }

            Spacer(minLength: 6)

            Button {
                motor.pedirLanzar(pieza.id)
            } label: {
                Label("Lanzar", systemImage: "play.fill")
            }
            .buttonStyle(BotonCabina(color: enPantalla ? Paleta.panel : Paleta.ambar, oscuro: !enPantalla))
            .fixedSize()
            .disabled(falta)
            .help(pieza.tipo == .video ? "Proyectar este vídeo desde el principio" : "Mostrar esta imagen en el proyector")

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
        Button("Lanzar") { motor.pedirLanzar(pieza.id) }
            .disabled(falta)
        Button("Renombrar") { editando = pieza.id }
        Button("Localizar archivo…") { motor.localizar(pieza.id) }
        Divider()
        Button("Quitar de la lista", role: .destructive) { motor.quitar(pieza.id) }
    }

    private var icono: String {
        if falta { return "exclamationmark.triangle.fill" }
        return pieza.tipo == .video ? "film" : "photo"
    }

    private var detalle: String {
        if falta { return "NO SE ENCUENTRA EL ARCHIVO" }
        let base: String
        switch pieza.tipo {
        case .video:
            base = pieza.duracion.map { Tiempo.texto($0) } ?? "--:--"
        case .imagen:
            base = "Imagen fija"
        }
        if enPantalla { return "EN PANTALLA · " + base }
        if pasada { return "Ya proyectada · " + base }
        return base
    }
}

// MARK: Panel de control

struct PanelControl: View {
    @EnvironmentObject private var motor: Motor
    @EnvironmentObject private var salida: Salida
    @State private var arrastre: Double?

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
        if motor.esImagen { return "IMAGEN EN PANTALLA" }
        return motor.hayFondo ? "FONDO EN PANTALLA" : "PANTALLA EN NEGRO"
    }

    private var iconoEstado: String {
        if motor.negro { return "moon.fill" }
        if motor.esVideo { return motor.reproduciendo ? "play.fill" : "pause.fill" }
        if motor.esImagen { return "photo.fill" }
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

            Image(systemName: motor.funcion.volumen == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(Paleta.tenue)
            Slider(value: $motor.funcion.volumen, in: 0...1)
                .frame(minWidth: 70, maxWidth: 150)
                .help("Volumen")
            Text("\(Int((motor.funcion.volumen * 100).rounded())) %")
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
        .help("Tapa la pantalla al instante sin perder el punto del vídeo")
    }

    private var pie: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A CONTINUACIÓN")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Paleta.tenue)
                if let siguiente = motor.siguiente {
                    Text(siguiente.nombre)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(siguiente.tipo == .video ? (siguiente.duracion.map { Tiempo.texto($0) } ?? "--:--") : "Imagen")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Paleta.tenue)
                    Button {
                        motor.lanzarSiguiente()
                    } label: {
                        Label("Lanzar la siguiente", systemImage: "forward.end.fill")
                    }
                    .buttonStyle(BotonCabina(color: Paleta.panel))
                    .help("⌘→")
                } else {
                    Text(motor.funcion.piezas.isEmpty ? "Añade piezas a la lista" : "Fin de la lista")
                        .font(.system(size: 15))
                        .foregroundStyle(Paleta.tenue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("FONDO ENTRE PELÍCULAS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Paleta.tenue)
                Text(nombreFondo)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Se ve cuando termina un vídeo")
                    .font(.system(size: 12))
                    .foregroundStyle(Paleta.tenue)
                HStack(spacing: 8) {
                    Button("Elegir imagen…") { motor.pedirFondo() }
                        .buttonStyle(BotonCabina(color: Paleta.panel))
                    if motor.funcion.rutaFondo != nil {
                        Button("Quitar") { motor.quitarFondo() }
                            .buttonStyle(BotonCabina(color: Paleta.panel))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nombreFondo: String {
        guard let ruta = motor.funcion.rutaFondo else { return "Negro" }
        return URL(fileURLWithPath: ruta).lastPathComponent
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
