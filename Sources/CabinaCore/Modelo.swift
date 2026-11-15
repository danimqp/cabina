import Foundation

/// Tipo de pieza que admite una función.
public enum TipoPieza: String, Codable, Sendable {
    case video
    case imagen
    /// Mensaje de texto escrito en la propia app; no tiene archivo.
    case texto

    public static let extensionesVideo: Set<String> = ["mp4", "mov", "m4v"]
    public static let extensionesImagen: Set<String> = ["jpg", "jpeg", "png"]

    /// Devuelve el tipo según la extensión, o `nil` si el formato no se admite.
    public static func deArchivo(_ url: URL) -> TipoPieza? {
        let ext = url.pathExtension.lowercased()
        if extensionesVideo.contains(ext) { return .video }
        if extensionesImagen.contains(ext) { return .imagen }
        return nil
    }
}

/// Un elemento de la lista: un vídeo o una imagen.
public struct Pieza: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var nombre: String
    public var ruta: String
    public var tipo: TipoPieza
    public var duracion: Double?
    /// Contenido de un mensaje de texto.
    public var texto: String?
    /// Punto donde se cortó el vídeo la última vez, para poder seguir desde ahí.
    public var posicion: Double?
    /// Volumen propio de la pieza; si no tiene, usa el general.
    public var volumen: Double?
    /// Archivo .srt de subtítulos.
    public var subtitulos: String?
    /// Recorte: segundo en el que empieza y en el que termina la proyección.
    public var inicio: Double?
    public var fin: Double?
    /// Al terminar, lanza sola la pieza siguiente.
    public var encadena: Bool?

    public init(
        id: UUID = UUID(), nombre: String, ruta: String, tipo: TipoPieza, duracion: Double? = nil,
        texto: String? = nil, posicion: Double? = nil, volumen: Double? = nil
    ) {
        self.id = id
        self.nombre = nombre
        self.ruta = ruta
        self.tipo = tipo
        self.duracion = duracion
        self.texto = texto
        self.posicion = posicion
        self.volumen = volumen
    }

    public static func mensaje(_ texto: String) -> Pieza {
        let titulo = texto.split(whereSeparator: \.isNewline).first.map(String.init) ?? texto
        return Pieza(nombre: titulo, ruta: "", tipo: .texto, texto: texto)
    }

    public var url: URL { URL(fileURLWithPath: ruta) }
}

/// La programación completa: lista ordenada de piezas y sus ajustes.
public struct Funcion: Codable, Equatable, Sendable {
    public var nombre: String
    public var piezas: [Pieza]
    public var rutaFondo: String?
    public var volumen: Double
    /// Archivos de audio de la música de espera.
    public var musica: [String]
    public var volumenMusica: Double

    public init(
        nombre: String = "Función sin título", piezas: [Pieza] = [], rutaFondo: String? = nil,
        volumen: Double = 1, musica: [String] = [], volumenMusica: Double = 0.6
    ) {
        self.nombre = nombre
        self.piezas = piezas
        self.rutaFondo = rutaFondo
        self.volumen = volumen
        self.musica = musica
        self.volumenMusica = volumenMusica
    }

    enum CodingKeys: String, CodingKey {
        case nombre, piezas, rutaFondo, volumen, musica, volumenMusica
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = try c.decodeIfPresent(String.self, forKey: .nombre) ?? "Función sin título"
        piezas = try c.decodeIfPresent([Pieza].self, forKey: .piezas) ?? []
        rutaFondo = try c.decodeIfPresent(String.self, forKey: .rutaFondo)
        volumen = try c.decodeIfPresent(Double.self, forKey: .volumen) ?? 1
        musica = try c.decodeIfPresent([String].self, forKey: .musica) ?? []
        volumenMusica = try c.decodeIfPresent(Double.self, forKey: .volumenMusica) ?? 0.6
    }

    /// Duración de los vídeos que aún no se han proyectado.
    public func duracionPendiente(sinContar pasadas: Set<UUID>) -> Double {
        piezas.reduce(0) { $0 + (pasadas.contains($1.id) ? 0 : ($1.duracion ?? 0)) }
    }

    public func indice(_ id: UUID?) -> Int? {
        guard let id else { return nil }
        return piezas.firstIndex { $0.id == id }
    }

    /// Suma de las duraciones conocidas de los vídeos.
    public var duracionTotal: Double {
        piezas.reduce(0) { $0 + ($1.duracion ?? 0) }
    }

    /// Añade los archivos admitidos y devuelve cuántos entraron.
    @discardableResult
    public mutating func agregar(_ urls: [URL]) -> Int {
        var cuenta = 0
        for url in urls {
            guard let tipo = TipoPieza.deArchivo(url) else { continue }
            let nombre = url.deletingPathExtension().lastPathComponent
            piezas.append(Pieza(nombre: nombre, ruta: url.path, tipo: tipo))
            cuenta += 1
        }
        return cuenta
    }

    /// Reordena igual que la lista del sistema: `destino` es la posición antes de quitar las movidas.
    public mutating func mover(desde origen: IndexSet, a destino: Int) {
        let validos = origen.filter { $0 >= 0 && $0 < piezas.count }
        guard !validos.isEmpty else { return }
        let movidas = validos.map { piezas[$0] }
        let antes = validos.filter { $0 < destino }.count
        for i in validos.sorted(by: >) { piezas.remove(at: i) }
        let posicion = max(0, min(piezas.count, destino - antes))
        piezas.insert(contentsOf: movidas, at: posicion)
    }

    public mutating func quitar(_ id: UUID) {
        piezas.removeAll { $0.id == id }
    }

    public func pieza(_ id: UUID?) -> Pieza? {
        guard let id else { return nil }
        return piezas.first { $0.id == id }
    }

    /// La pieza que sigue a la indicada; si no hay referencia, la primera.
    public func siguiente(a id: UUID?) -> Pieza? {
        guard !piezas.isEmpty else { return nil }
        guard let id, let i = piezas.firstIndex(where: { $0.id == id }) else { return piezas.first }
        return i + 1 < piezas.count ? piezas[i + 1] : nil
    }
}

public enum Tiempo {
    /// 75 → "01:15"; 3725 → "1:02:05".
    public static func texto(_ segundos: Double) -> String {
        guard segundos.isFinite, segundos > 0 else { return "00:00" }
        let total = Int(segundos.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

/// Una línea de subtítulo con su intervalo en segundos.
public struct Subtitulo: Equatable, Sendable {
    public let inicio: Double
    public let fin: Double
    public let texto: String

    public init(inicio: Double, fin: Double, texto: String) {
        self.inicio = inicio
        self.fin = fin
        self.texto = texto
    }
}

/// Lector de archivos de subtítulos .srt.
public enum SRT {
    public static func leer(_ contenido: String) -> [Subtitulo] {
        let lineas = contenido
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: "\n")
        var bloques: [[String]] = [[]]
        for linea in lineas {
            if linea.trimmingCharacters(in: .whitespaces).isEmpty {
                if !(bloques.last ?? []).isEmpty { bloques.append([]) }
            } else {
                bloques[bloques.count - 1].append(linea)
            }
        }
        var resultado: [Subtitulo] = []
        for bloque in bloques {
            guard let i = bloque.firstIndex(where: { $0.contains("-->") }) else { continue }
            let partes = bloque[i].components(separatedBy: "-->")
            guard partes.count == 2, let a = segundos(partes[0]), let b = segundos(partes[1]), b > a else { continue }
            let texto = bloque[(i + 1)...].map(limpiar).filter { !$0.isEmpty }.joined(separator: "\n")
            guard !texto.isEmpty else { continue }
            resultado.append(Subtitulo(inicio: a, fin: b, texto: texto))
        }
        return resultado.sorted { $0.inicio < $1.inicio }
    }

    /// "00:01:02,500" → 62.5
    static func segundos(_ campo: String) -> Double? {
        guard let marca = campo.split(separator: " ").first else { return nil }
        let partes = marca.replacingOccurrences(of: ",", with: ".").split(separator: ":").map { Double($0) }
        guard partes.count == 2 || partes.count == 3, !partes.contains(where: { $0 == nil }) else { return nil }
        return partes.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    /// Quita etiquetas de formato como <i> o {\an8}.
    static func limpiar(_ linea: String) -> String {
        var salida = ""
        var dentro: Character?
        for c in linea {
            if let cierre = dentro {
                if c == cierre { dentro = nil }
            } else if c == "<" {
                dentro = ">"
            } else if c == "{" {
                dentro = "}"
            } else {
                salida.append(c)
            }
        }
        return salida.trimmingCharacters(in: .whitespaces)
    }

    /// El texto que toca en el segundo `t`, o vacío.
    public static func texto(en t: Double, de lista: [Subtitulo]) -> String {
        for s in lista {
            if s.inicio > t { break }
            if t < s.fin { return s.texto }
        }
        return ""
    }
}
