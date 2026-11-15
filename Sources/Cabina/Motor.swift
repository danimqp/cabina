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
    /// Imagen fija o mensaje de texto.
    case imagen(UUID)
}

/// Resultado de comprobar una pieza antes de la función.
struct Problema: Equatable {
    let texto: String
    /// `true` si la pieza no se va a poder proyectar.
    let grave: Bool
}

/// Estado y lógica de la función: lista, reproducción, negro, música y guardado.
@MainActor
final class Motor: ObservableObject {
    @Published var funcion = Funcion() {
        didSet { alCambiarFuncion(anterior: oldValue) }
    }
    @Published var seleccion: UUID?
    @Published var aviso: String?
    /// Pieza que espera confirmación porque hay un vídeo en marcha.
    @Published var pendiente: UUID?
    /// Mensaje rápido que espera confirmación por el mismo motivo.
    @Published var mensajePendiente: String?

    @Published private(set) var contenido: Contenido = .fondo
    @Published private(set) var imagenVisible: NSImage?
    @Published private(set) var negro = false
    @Published private(set) var reproduciendo = false
    @Published private(set) var tiempo: Double = 0
    @Published private(set) var duracion: Double = 0
    @Published private(set) var tituloEnPantalla = ""
    @Published private(set) var esMensaje = false
    @Published private(set) var pasadas: Set<UUID> = []
    @Published private(set) var faltantes: Set<UUID> = []
    @Published private(set) var problemas: [UUID: Problema] = [:]
    @Published private(set) var comprobando = false
    @Published private(set) var nota: String?
    @Published private(set) var ultimoLanzado: UUID?

    @Published private(set) var musicaEncendida = false
    @Published private(set) var pistaMusica = ""
    @Published private(set) var dispositivos: [DispositivoAudio] = []
    @Published private(set) var salidaAudio: String?

    let player = AVPlayer()
    let musica = AVPlayer()

    private var imagenFondo: NSImage?
    private var salidaVideo: AVPlayerItemVideoOutput?
    private let contextoCI = CIContext()
    private var reanudarTrasNegro = false
    private var observadorTiempo: Any?
    private var observadores: [NSObjectProtocol] = []
    private var tareaGuardado: Task<Void, Never>?
    private var tareaFundido: Task<Void, Never>?
    private var tareaComprobar: Task<Void, Never>?
    private var indiceMusica = 0
    private var tics = 0
    private let persistir: Bool

    private static let claveAudio = "salidaAudio"

    // MARK: Arranque

    init() {
        persistir = ProcessInfo.processInfo.environment["CABINA_PRUEBA"] == nil
        player.actionAtItemEnd = .pause
        player.allowsExternalPlayback = false
        musica.actionAtItemEnd = .pause
        musica.allowsExternalPlayback = false

        if persistir, let datos = try? Data(contentsOf: Self.archivoAutomatico),
           let guardada = try? JSONDecoder().decode(Funcion.self, from: datos) {
            funcion = guardada
        }
        player.volume = Float(funcion.volumen)
        cargarFondo()
        imagenVisible = imagenFondo
        verificarArchivos()
        cargarDuraciones()
        actualizarDispositivos()
        if persistir, let guardado = UserDefaults.standard.string(forKey: Self.claveAudio),
           dispositivos.contains(where: { $0.uid == guardado }) {
            aplicarSalidaAudio(guardado)
        }
        comprobar(avisar: false)

        observadorTiempo = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 5), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tic() }
        }
        let centro = NotificationCenter.default
        observadores.append(centro.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notificacion in
            MainActor.assumeIsolated { self?.finDeElemento(notificacion.object as AnyObject?) }
        })
        observadores.append(centro.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.guardarPosicionActual()
                self?.guardarAhora()
            }
        })
        observadores.append(centro.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.verificarArchivos()
                self?.actualizarDispositivos()
            }
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

    var musicaSonando: Bool { musica.rate != 0 }

    /// Segundos de vídeo que quedan por proyectar, contando lo que falta del actual.
    var duracionPorDelante: Double {
        var excluidas = pasadas
        if let id = idEnPantalla { excluidas.insert(id) }
        return funcion.duracionPendiente(sinContar: excluidas) + (esVideo ? restante : 0)
    }

    // MARK: Lanzar

    /// Lanza la pieza; si hay un vídeo en marcha, pide confirmación antes de cortarlo.
    func pedirLanzar(_ id: UUID, desdeElPrincipio: Bool = false) {
        if desdeElPrincipio, let i = funcion.indice(id), funcion.piezas[i].posicion != nil {
            funcion.piezas[i].posicion = nil
        }
        if hayQueConfirmarCorte {
            pendiente = id
        } else {
            lanzar(id, desde: funcion.pieza(id)?.posicion)
        }
    }

    func pedirMensaje(_ texto: String) {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        if hayQueConfirmarCorte {
            mensajePendiente = limpio
        } else {
            mostrarMensaje(limpio)
        }
    }

    private var hayQueConfirmarCorte: Bool { esVideo && reproduciendo && restante > 3 }

    var hayPendiente: Bool { pendiente != nil || mensajePendiente != nil }

    var nombrePendiente: String {
        if let mensajePendiente { return mensajePendiente }
        return funcion.pieza(pendiente)?.nombre ?? ""
    }

    func confirmarPendiente() {
        if let texto = mensajePendiente {
            cancelarPendiente()
            mostrarMensaje(texto)
        } else if let id = pendiente {
            cancelarPendiente()
            lanzar(id, desde: id == idEnPantalla ? nil : funcion.pieza(id)?.posicion)
        }
    }

    func cancelarPendiente() {
        pendiente = nil
        mensajePendiente = nil
    }

    func lanzarSiguiente() {
        guard let pieza = siguiente else { return }
        pedirLanzar(pieza.id)
    }

    func lanzarSeleccionada() {
        guard let id = seleccion else { return }
        pedirLanzar(id)
    }

    func lanzar(_ id: UUID, desde inicio: Double? = nil) {
        guard let pieza = funcion.pieza(id) else { return }
        if pieza.tipo != .texto {
            guard FileManager.default.fileExists(atPath: pieza.ruta) else {
                faltantes.insert(id)
                aviso = "No se encuentra el archivo de «\(pieza.nombre)». El proyector no ha cambiado. Usa «Localizar archivo…» en el menú de la pieza."
                return
            }
            faltantes.remove(id)
        }

        switch pieza.tipo {
        case .video:
            let item = AVPlayerItem(url: pieza.url)
            let salida = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            item.add(salida)
            dejarLaActual()
            salidaVideo = salida
            player.replaceCurrentItem(with: item)
            player.volume = Float(pieza.volumen ?? funcion.volumen)
            let arranque = max(0, inicio ?? 0)
            if arranque > 0 {
                player.seek(
                    to: CMTime(seconds: arranque, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero
                )
            }
            imagenVisible = nil
            contenido = .video(id)
            tiempo = arranque
            duracion = pieza.duracion ?? 0
            esMensaje = false
            player.play()
            reproduciendo = true
            callarMusica()

        case .imagen:
            guard let imagen = NSImage(contentsOf: pieza.url), imagen.isValid else {
                aviso = "No se pudo abrir la imagen «\(pieza.nombre)». El proyector no ha cambiado."
                return
            }
            ponerImagen(imagen, id: id, mensaje: false)

        case .texto:
            ponerImagen(Rotulo.imagen(pieza.texto ?? pieza.nombre), id: id, mensaje: true)
        }

        tituloEnPantalla = pieza.nombre
        ultimoLanzado = id
        pasadas.remove(id)
        reanudarTrasNegro = false
        negro = false
        aviso = nil
    }

    /// Muestra un mensaje escrito al momento, sin añadirlo a la lista.
    func mostrarMensaje(_ texto: String) {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        ponerImagen(Rotulo.imagen(limpio), id: UUID(), mensaje: true)
        tituloEnPantalla = limpio
        reanudarTrasNegro = false
        negro = false
    }

    private func ponerImagen(_ imagen: NSImage, id: UUID, mensaje: Bool) {
        dejarLaActual()
        player.pause()
        player.replaceCurrentItem(with: nil)
        salidaVideo = nil
        imagenVisible = imagen
        contenido = .imagen(id)
        esMensaje = mensaje
        tiempo = 0
        duracion = 0
        reproduciendo = false
        retomarMusica()
    }

    /// Retira la pieza y deja la imagen de fondo (o negro).
    func volverAlFondo() {
        retirar(terminada: false)
    }

    private func retirar(terminada: Bool) {
        if terminada, case .video(let id) = contenido, let i = funcion.indice(id) {
            if funcion.piezas[i].posicion != nil { funcion.piezas[i].posicion = nil }
            pasadas.insert(id)
        } else {
            dejarLaActual()
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        salidaVideo = nil
        imagenVisible = imagenFondo
        contenido = .fondo
        esMensaje = false
        reproduciendo = false
        reanudarTrasNegro = false
        tiempo = 0
        duracion = 0
        tituloEnPantalla = ""
        retomarMusica()
    }

    /// Antes de cambiar de pieza: marca la actual como pasada y recuerda por dónde iba.
    private func dejarLaActual() {
        guardarPosicionActual()
        if let id = idEnPantalla, funcion.indice(id) != nil { pasadas.insert(id) }
    }

    /// Recuerda el punto del vídeo en marcha para poder seguir desde ahí tras un corte.
    private func guardarPosicionActual() {
        guard case .video(let id) = contenido, let i = funcion.indice(id) else { return }
        let t = player.currentTime().seconds
        guard t.isFinite, duracion > 0 else { return }
        let guardada = funcion.piezas[i].posicion
        if duracion - t <= 5 {
            if guardada != nil { funcion.piezas[i].posicion = nil }
        } else if t > 5, guardada == nil || t > (guardada ?? 0) || t > 30 {
            funcion.piezas[i].posicion = t
        }
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
        tics += 1
        if tics % 25 == 0 { guardarPosicionActual() }
    }

    private func finDeElemento(_ objeto: AnyObject?) {
        guard let objeto else { return }
        if let item = musica.currentItem, objeto === item {
            siguientePista()
        } else if esVideo, let item = player.currentItem, objeto === item {
            retirar(terminada: true)
        }
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

    // MARK: Volumen y salida de sonido

    /// El volumen del vídeo en pantalla (el suyo propio si lo tiene) o el general.
    var volumenActual: Double {
        if case .video(let id) = contenido, let propio = funcion.pieza(id)?.volumen { return propio }
        return funcion.volumen
    }

    var volumenEsDeLaPieza: Bool {
        if case .video(let id) = contenido { return funcion.indice(id) != nil }
        return false
    }

    /// Con un vídeo en pantalla ajusta y recuerda el volumen de ese vídeo; si no, el general.
    func fijarVolumen(_ valor: Double) {
        let v = max(0, min(1, valor))
        if case .video(let id) = contenido, let i = funcion.indice(id) {
            funcion.piezas[i].volumen = v
        } else {
            funcion.volumen = v
        }
        player.volume = Float(v)
    }

    func actualizarDispositivos() {
        let nuevos = Audio.salidas()
        if nuevos != dispositivos { dispositivos = nuevos }
        if let actual = salidaAudio, !nuevos.contains(where: { $0.uid == actual }) {
            aplicarSalidaAudio(nil)
            aviso = "La salida de sonido elegida ya no está conectada. El sonido vuelve a la salida del sistema."
        }
    }

    func elegirSalidaAudio(_ uid: String?) {
        aplicarSalidaAudio(uid)
        guard persistir else { return }
        if let uid {
            UserDefaults.standard.set(uid, forKey: Self.claveAudio)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.claveAudio)
        }
    }

    private func aplicarSalidaAudio(_ uid: String?) {
        salidaAudio = uid
        player.audioOutputDeviceUniqueID = uid
        musica.audioOutputDeviceUniqueID = uid
    }

    // MARK: Música de espera

    private static let extensionesAudio = ["mp3", "m4a", "aac", "wav", "aiff", "aif"]

    func pedirMusica() {
        let panel = NSOpenPanel()
        panel.title = "Música de espera"
        panel.message = "Elige una o varias canciones. Sonarán en bucle mientras no haya un vídeo en pantalla."
        panel.prompt = "Usar esta música"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.extensionesAudio.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        fijarMusica(panel.urls)
        encenderMusica()
    }

    func fijarMusica(_ urls: [URL]) {
        let ordenadas = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        funcion.musica = ordenadas.map(\.path)
        indiceMusica = 0
        musica.pause()
        musica.replaceCurrentItem(with: nil)
        pistaMusica = ""
    }

    func alternarMusica() {
        if musicaEncendida { apagarMusica() } else { encenderMusica() }
    }

    func encenderMusica() {
        guard !funcion.musica.isEmpty else {
            pedirMusica()
            return
        }
        musicaEncendida = true
        retomarMusica()
    }

    func apagarMusica() {
        musicaEncendida = false
        fundirMusica(a: 0, pausar: true)
    }

    /// La música suena solo si está encendida y no hay un vídeo en pantalla.
    private func retomarMusica() {
        guard musicaEncendida, !esVideo else { return }
        if musica.currentItem == nil, !cargarPista() {
            musicaEncendida = false
            aviso = "No se encuentra ningún archivo de la música de espera."
            return
        }
        if musica.rate == 0 {
            musica.volume = 0
            musica.play()
        }
        fundirMusica(a: Float(funcion.volumenMusica), pausar: false)
    }

    private func callarMusica() {
        guard musica.rate != 0 || tareaFundido != nil else { return }
        fundirMusica(a: 0, pausar: true)
    }

    private func cargarPista() -> Bool {
        let rutas = funcion.musica
        guard !rutas.isEmpty else { return false }
        for salto in 0..<rutas.count {
            let i = (indiceMusica + salto) % rutas.count
            guard FileManager.default.fileExists(atPath: rutas[i]) else { continue }
            indiceMusica = i
            let url = URL(fileURLWithPath: rutas[i])
            musica.replaceCurrentItem(with: AVPlayerItem(url: url))
            pistaMusica = url.deletingPathExtension().lastPathComponent
            return true
        }
        return false
    }

    private func siguientePista() {
        indiceMusica += 1
        guard cargarPista() else {
            musicaEncendida = false
            return
        }
        if musicaEncendida, !esVideo { musica.play() }
    }

    private func fundirMusica(a destino: Float, pausar: Bool) {
        tareaFundido?.cancel()
        let inicio = musica.volume
        tareaFundido = Task { [weak self] in
            let pasos = 8
            for paso in 1...pasos {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled, let self else { return }
                self.musica.volume = inicio + (destino - inicio) * Float(paso) / Float(pasos)
            }
            guard !Task.isCancelled, let self else { return }
            if pausar { self.musica.pause() }
            self.tareaFundido = nil
        }
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
        comprobar(avisar: false)
        return n
    }

    /// Guarda un mensaje de texto como pieza de la lista, para reutilizarlo.
    func agregarMensaje(_ texto: String) {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        funcion.piezas.append(Pieza.mensaje(limpio))
    }

    func quitar(_ id: UUID) {
        funcion.quitar(id)
        pasadas.remove(id)
        faltantes.remove(id)
        problemas[id] = nil
        if seleccion == id { seleccion = nil }
        if pendiente == id { pendiente = nil }
    }

    func renombrar(_ id: UUID, _ nombre: String) {
        let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, let i = funcion.indice(id) else { return }
        funcion.piezas[i].nombre = limpio
        if funcion.piezas[i].tipo == .texto {
            funcion.piezas[i].texto = limpio
            if idEnPantalla == id { imagenVisible = Rotulo.imagen(limpio) }
        }
        if idEnPantalla == id { tituloEnPantalla = limpio }
    }

    func verificarArchivos() {
        let nuevos = Set(funcion.piezas
            .filter { $0.tipo != .texto && !FileManager.default.fileExists(atPath: $0.ruta) }
            .map(\.id))
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
        guard let i = funcion.indice(id) else { return }
        funcion.piezas[i].duracion = segundos
    }

    // MARK: Comprobar la función

    /// Abre cada archivo para detectar, antes de proyectar, los que no van a funcionar.
    func comprobar(avisar: Bool) {
        tareaComprobar?.cancel()
        verificarArchivos()
        let piezas = funcion.piezas.filter { $0.tipo != .texto }
        if avisar {
            comprobando = true
            nota = nil
        }
        tareaComprobar = Task { [weak self] in
            var hallados: [UUID: Problema] = [:]
            for pieza in piezas {
                guard FileManager.default.fileExists(atPath: pieza.ruta) else { continue }
                switch pieza.tipo {
                case .video:
                    let recurso = AVURLAsset(url: pieza.url)
                    let reproducible = (try? await recurso.load(.isPlayable)) ?? false
                    let pistasImagen = (try? await recurso.loadTracks(withMediaType: .video)) ?? []
                    let pistasSonido = (try? await recurso.loadTracks(withMediaType: .audio)) ?? []
                    if !reproducible || pistasImagen.isEmpty {
                        hallados[pieza.id] = Problema(texto: "ESTE VÍDEO NO SE PUEDE REPRODUCIR", grave: true)
                    } else if pistasSonido.isEmpty {
                        hallados[pieza.id] = Problema(texto: "Sin sonido", grave: false)
                    }
                case .imagen:
                    let imagen = NSImage(contentsOf: pieza.url)
                    if imagen == nil || imagen?.isValid == false {
                        hallados[pieza.id] = Problema(texto: "ESTA IMAGEN NO SE PUEDE ABRIR", grave: true)
                    }
                case .texto:
                    break
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.problemas = hallados
            self.comprobando = false
            guard avisar else { return }
            let graves = hallados.values.filter { $0.grave }.count + self.faltantes.count
            let mudos = hallados.values.filter { !$0.grave }.count
            if graves > 0 {
                self.nota = nil
                self.aviso = "\(graves) pieza(s) no se van a poder proyectar. Están marcadas en rojo en la lista."
            } else if mudos > 0 {
                self.nota = "Comprobado: todo se puede proyectar. \(mudos) vídeo(s) sin sonido."
            } else {
                self.nota = "Comprobado: todo listo para proyectar."
            }
        }
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
        guard let i = funcion.indice(id) else { return }
        let panel = NSOpenPanel()
        panel.title = "Localizar «\(funcion.piezas[i].nombre)»"
        panel.prompt = "Elegir"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.tiposAdmitidos
        guard panel.runModal() == .OK, let url = panel.url, let tipo = TipoPieza.deArchivo(url) else { return }
        funcion.piezas[i].ruta = url.path
        funcion.piezas[i].tipo = tipo
        funcion.piezas[i].duracion = nil
        funcion.piezas[i].posicion = nil
        verificarArchivos()
        cargarDuraciones()
        comprobar(avisar: false)
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
        apagarMusica()
        musica.replaceCurrentItem(with: nil)
        pistaMusica = ""
        indiceMusica = 0
        negro = false
        pasadas = []
        problemas = [:]
        nota = nil
        ultimoLanzado = nil
        seleccion = nil
        cancelarPendiente()
        funcion = nueva
        player.volume = Float(nueva.volumen)
        cargarFondo()
        imagenVisible = imagenFondo
        verificarArchivos()
        cargarDuraciones()
        comprobar(avisar: false)
    }

    // MARK: Fondo y guardado

    private func alCambiarFuncion(anterior: Funcion) {
        guard funcion != anterior else { return }
        if funcion.volumenMusica != anterior.volumenMusica, musica.rate != 0, tareaFundido == nil {
            musica.volume = Float(funcion.volumenMusica)
        }
        if funcion.rutaFondo != anterior.rutaFondo {
            cargarFondo()
            if contenido == .fondo { imagenVisible = imagenFondo }
        }
        if funcion.piezas.count != anterior.piezas.count, nota != nil {
            nota = nil
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
