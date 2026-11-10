import AppKit
import AVFoundation
import CabinaCore
import Combine
import CoreImage
import UniformTypeIdentifiers

/// Lo que hay ahora mismo en la salida del público.
enum Contenido: Equatable {
    /// Ninguna pieza: se ve la imagen de fondo o, si no hay, negro.
    case fondo
    case video(UUID)
    case imagen(UUID)
}

/// Estado y lógica de la función: lista, reproducción, negro y guardado.
@MainActor
final class Motor: ObservableObject {
    @Published var funcion = Funcion() {
        didSet { alCambiarFuncion(anterior: oldValue) }
    }
    @Published var seleccion: UUID?
    @Published var aviso: String?
    /// Pieza que espera confirmación porque hay un vídeo en marcha.
    @Published var pendiente: UUID?

    @Published private(set) var contenido: Contenido = .fondo
    @Published private(set) var imagenVisible: NSImage?
    @Published private(set) var negro = false
    @Published private(set) var reproduciendo = false
    @Published private(set) var tiempo: Double = 0
    @Published private(set) var duracion: Double = 0
    @Published private(set) var tituloEnPantalla = ""
    @Published private(set) var pasadas: Set<UUID> = []
    @Published private(set) var faltantes: Set<UUID> = []
    @Published private(set) var ultimoLanzado: UUID?

    let player = AVPlayer()

    private var imagenFondo: NSImage?
    private var salidaVideo: AVPlayerItemVideoOutput?
    private let contextoCI = CIContext()
    private var reanudarTrasNegro = false
    private var observadorTiempo: Any?
    private var observadores: [NSObjectProtocol] = []
    private var tareaGuardado: Task<Void, Never>?
    private let persistir: Bool

    // MARK: Arranque

    init() {
        persistir = ProcessInfo.processInfo.environment["CABINA_PRUEBA"] == nil
        player.actionAtItemEnd = .pause
        player.allowsExternalPlayback = false

        if persistir, let datos = try? Data(contentsOf: Self.archivoAutomatico),
           let guardada = try? JSONDecoder().decode(Funcion.self, from: datos) {
            funcion = guardada
        }
        player.volume = Float(funcion.volumen)
        cargarFondo()
        imagenVisible = imagenFondo
        verificarArchivos()
        cargarDuraciones()

        observadorTiempo = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 5), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tic() }
        }
        let centro = NotificationCenter.default
        observadores.append(centro.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] nota in
            MainActor.assumeIsolated { self?.finDeVideo(nota.object as AnyObject?) }
        })
        observadores.append(centro.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.guardarAhora() }
        })
        observadores.append(centro.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.verificarArchivos() }
        })
    }

    // MARK: Consultas

    var esVideo: Bool {
        if case .video = contenido { return true }
        return false
    }

    var esImagen: Bool {
        if case .imagen = contenido { return true }
        return false
    }

    var idEnPantalla: UUID? {
        switch contenido {
        case .fondo: return nil
        case .video(let id), .imagen(let id): return id
        }
    }

    var restante: Double { max(0, duracion - tiempo) }

    var siguiente: Pieza? { funcion.siguiente(a: ultimoLanzado) }

    var hayFondo: Bool { imagenFondo != nil }

    // MARK: Lanzar

    /// Lanza la pieza; si hay un vídeo en marcha, pide confirmación antes de cortarlo.
    func pedirLanzar(_ id: UUID) {
        if esVideo, reproduciendo, restante > 3, idEnPantalla != id {
            pendiente = id
        } else {
            lanzar(id)
        }
    }

    func confirmarPendiente() {
        guard let id = pendiente else { return }
        pendiente = nil
        lanzar(id)
    }

    func lanzarSiguiente() {
        guard let pieza = siguiente else { return }
        pedirLanzar(pieza.id)
    }

    func lanzarSeleccionada() {
        guard let id = seleccion else { return }
        pedirLanzar(id)
    }

    func lanzar(_ id: UUID) {
        guard let pieza = funcion.pieza(id) else { return }
        guard FileManager.default.fileExists(atPath: pieza.ruta) else {
            faltantes.insert(id)
            aviso = "No se encuentra el archivo de «\(pieza.nombre)». El proyector no ha cambiado. Usa «Localizar archivo…» en el menú de la pieza."
            return
        }
        faltantes.remove(id)

        switch pieza.tipo {
        case .video:
            let item = AVPlayerItem(url: pieza.url)
            let salida = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            item.add(salida)
            marcarPasadaLaActual()
            salidaVideo = salida
            player.replaceCurrentItem(with: item)
            player.volume = Float(funcion.volumen)
            imagenVisible = nil
            contenido = .video(id)
            tiempo = 0
            duracion = pieza.duracion ?? 0
            player.play()
            reproduciendo = true

        case .imagen:
            guard let imagen = NSImage(contentsOf: pieza.url), imagen.isValid else {
                aviso = "No se pudo abrir la imagen «\(pieza.nombre)». El proyector no ha cambiado."
                return
            }
            marcarPasadaLaActual()
            player.pause()
            player.replaceCurrentItem(with: nil)
            salidaVideo = nil
            imagenVisible = imagen
            contenido = .imagen(id)
            tiempo = 0
            duracion = 0
            reproduciendo = false
        }

        tituloEnPantalla = pieza.nombre
        ultimoLanzado = id
        pasadas.remove(id)
        reanudarTrasNegro = false
        negro = false
        aviso = nil
    }

    /// Retira la pieza y deja la imagen de fondo (o negro).
    func volverAlFondo() {
        marcarPasadaLaActual()
        player.pause()
        player.replaceCurrentItem(with: nil)
        salidaVideo = nil
        imagenVisible = imagenFondo
        contenido = .fondo
        reproduciendo = false
        reanudarTrasNegro = false
        tiempo = 0
        duracion = 0
        tituloEnPantalla = ""
    }

    private func marcarPasadaLaActual() {
        if let id = idEnPantalla { pasadas.insert(id) }
    }

    // MARK: Transporte

    func alternarReproduccion() {
        guard esVideo else { return }
        if player.rate != 0 {
            player.pause()
            reproduciendo = false
        } else {
            reanudarTrasNegro = false
            negro = false
            player.play()
            reproduciendo = true
        }
    }

    func alternarNegro() {
        if negro {
            negro = false
            if reanudarTrasNegro, esVideo {
                player.play()
                reproduciendo = true
            }
            reanudarTrasNegro = false
        } else {
            reanudarTrasNegro = esVideo && player.rate != 0
            player.pause()
            reproduciendo = false
            negro = true
        }
    }

    func buscar(_ segundos: Double) {
        guard esVideo else { return }
        let destino = max(0, min(segundos, max(0, duracion - 0.05)))
        tiempo = destino
        player.seek(
            to: CMTime(seconds: destino, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        )
    }

    private func tic() {
        guard esVideo, let item = player.currentItem else { return }
        if item.status == .failed {
            let nombre = tituloEnPantalla
            volverAlFondo()
            aviso = "No se pudo reproducir «\(nombre)». El formato puede no ser compatible. El proyector ha vuelto al fondo."
            return
        }
        let t = player.currentTime().seconds
        if t.isFinite { tiempo = t }
        let d = item.duration
        if d.isNumeric, d.seconds > 0 { duracion = d.seconds }
        let enMarcha = player.rate != 0
        if enMarcha != reproduciendo { reproduciendo = enMarcha }
    }

    private func finDeVideo(_ objeto: AnyObject?) {
        guard esVideo, let item = player.currentItem, objeto === item else { return }
        volverAlFondo()
    }

    /// Fotograma actual para la vista previa del operador (a tamaño reducido).
    func fotogramaPrevia() -> CGImage? {
        guard esVideo, let salida = salidaVideo else { return nil }
        let t = salida.itemTime(forHostTime: CACurrentMediaTime())
        guard salida.hasNewPixelBuffer(forItemTime: t),
              let buffer = salida.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { return nil }
        var imagen = CIImage(cvPixelBuffer: buffer)
        let ancho = imagen.extent.width
        if ancho > 640 {
            let escala = 640 / ancho
            imagen = imagen.transformed(by: CGAffineTransform(scaleX: escala, y: escala))
        }
        return contextoCI.createCGImage(imagen, from: imagen.extent)
    }

    // MARK: Lista

    @discardableResult
    func agregar(_ urls: [URL]) -> Int {
        let ordenadas = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let n = funcion.agregar(ordenadas)
        let descartados = urls.count - n
        if descartados > 0 {
            aviso = "\(descartados) archivo(s) no se añadieron: Cabina admite MP4, MOV, M4V, JPG y PNG."
        }
        cargarDuraciones()
        return n
    }

    func quitar(_ id: UUID) {
        funcion.quitar(id)
        pasadas.remove(id)
        faltantes.remove(id)
        if seleccion == id { seleccion = nil }
        if pendiente == id { pendiente = nil }
    }

    func renombrar(_ id: UUID, _ nombre: String) {
        let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, let i = funcion.piezas.firstIndex(where: { $0.id == id }) else { return }
        funcion.piezas[i].nombre = limpio
        if idEnPantalla == id { tituloEnPantalla = limpio }
    }

    func verificarArchivos() {
        let nuevos = Set(funcion.piezas.filter { !FileManager.default.fileExists(atPath: $0.ruta) }.map(\.id))
        if nuevos != faltantes { faltantes = nuevos }
    }

    private func cargarDuraciones() {
        for pieza in funcion.piezas where pieza.tipo == .video && pieza.duracion == nil {
            let id = pieza.id
            let url = pieza.url
            Task { [weak self] in
                let recurso = AVURLAsset(url: url)
                guard let d = try? await recurso.load(.duration), d.isNumeric else { return }
                self?.fijarDuracion(id, d.seconds)
            }
        }
    }

    private func fijarDuracion(_ id: UUID, _ segundos: Double) {
        guard let i = funcion.piezas.firstIndex(where: { $0.id == id }) else { return }
        funcion.piezas[i].duracion = segundos
    }

    // MARK: Diálogos de archivo

    private static var tiposAdmitidos: [UTType] {
        (Array(TipoPieza.extensionesVideo) + Array(TipoPieza.extensionesImagen))
            .compactMap { UTType(filenameExtension: $0) }
    }

    private static var tipoFuncion: UTType { UTType(filenameExtension: "cabina") ?? .json }

    func pedirArchivos() {
        let panel = NSOpenPanel()
        panel.title = "Añadir vídeos e imágenes"
        panel.prompt = "Añadir"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.tiposAdmitidos
        guard panel.runModal() == .OK else { return }
        agregar(panel.urls)
    }

    func pedirFondo() {
        let panel = NSOpenPanel()
        panel.title = "Imagen de fondo entre películas"
        panel.prompt = "Usar de fondo"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        funcion.rutaFondo = url.path
    }

    func quitarFondo() {
        funcion.rutaFondo = nil
    }

    func localizar(_ id: UUID) {
        guard let i = funcion.piezas.firstIndex(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.title = "Localizar «\(funcion.piezas[i].nombre)»"
        panel.prompt = "Elegir"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.tiposAdmitidos
        guard panel.runModal() == .OK, let url = panel.url, let tipo = TipoPieza.deArchivo(url) else { return }
        funcion.piezas[i].ruta = url.path
        funcion.piezas[i].tipo = tipo
        funcion.piezas[i].duracion = nil
        verificarArchivos()
        cargarDuraciones()
    }

    func nuevaFuncion() {
        if !funcion.piezas.isEmpty {
            let alerta = NSAlert()
            alerta.messageText = "¿Empezar una función nueva?"
            alerta.informativeText = "Se vaciará la lista actual. Los archivos de vídeo e imagen no se borran."
            alerta.addButton(withTitle: "Vaciar la lista")
            alerta.addButton(withTitle: "Cancelar")
            guard alerta.runModal() == .alertFirstButtonReturn else { return }
        }
        reemplazar(por: Funcion())
    }

    func abrirFuncion() {
        let panel = NSOpenPanel()
        panel.title = "Abrir función"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [Self.tipoFuncion, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let datos = try Data(contentsOf: url)
            reemplazar(por: try JSONDecoder().decode(Funcion.self, from: datos))
        } catch {
            aviso = "No se pudo abrir esa función: el archivo no es una función de Cabina."
        }
    }

    func guardarFuncionComo() {
        let panel = NSSavePanel()
        panel.title = "Guardar función"
        panel.allowedContentTypes = [Self.tipoFuncion]
        panel.nameFieldStringValue = funcion.nombre
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.codificar(funcion).write(to: url, options: .atomic)
        } catch {
            aviso = "No se pudo guardar la función en esa ubicación."
        }
    }

    private func reemplazar(por nueva: Funcion) {
        volverAlFondo()
        negro = false
        pasadas = []
        ultimoLanzado = nil
        seleccion = nil
        pendiente = nil
        funcion = nueva
        cargarFondo()
        imagenVisible = imagenFondo
        verificarArchivos()
        cargarDuraciones()
    }

    // MARK: Fondo y guardado

    private func alCambiarFuncion(anterior: Funcion) {
        guard funcion != anterior else { return }
        if funcion.volumen != anterior.volumen {
            player.volume = Float(funcion.volumen)
        }
        if funcion.rutaFondo != anterior.rutaFondo {
            cargarFondo()
            if contenido == .fondo { imagenVisible = imagenFondo }
        }
        programarGuardado()
    }

    private func cargarFondo() {
        guard let ruta = funcion.rutaFondo else {
            imagenFondo = nil
            return
        }
        if let imagen = NSImage(contentsOfFile: ruta), imagen.isValid {
            imagenFondo = imagen
        } else {
            imagenFondo = nil
            aviso = "No se encuentra la imagen de fondo. Entre películas se verá negro."
        }
    }

    private static var archivoAutomatico: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Cabina", isDirectory: true).appendingPathComponent("funcion.json")
    }

    private static func codificar(_ funcion: Funcion) throws -> Data {
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try codificador.encode(funcion)
    }

    private func programarGuardado() {
        guard persistir else { return }
        tareaGuardado?.cancel()
        tareaGuardado = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.guardarAhora()
        }
    }

    private func guardarAhora() {
        guard persistir else { return }
        let destino = Self.archivoAutomatico
        do {
            try FileManager.default.createDirectory(
                at: destino.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Self.codificar(funcion).write(to: destino, options: .atomic)
        } catch {
            aviso = "No se pudo guardar la función automáticamente."
        }
    }
}
