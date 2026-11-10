import Foundation

/// Tipo de pieza que admite una función.
public enum TipoPieza: String, Codable, Sendable {
    case video
    case imagen

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

    public init(id: UUID = UUID(), nombre: String, ruta: String, tipo: TipoPieza, duracion: Double? = nil) {
        self.id = id
        self.nombre = nombre
        self.ruta = ruta
        self.tipo = tipo
        self.duracion = duracion
    }

    public var url: URL { URL(fileURLWithPath: ruta) }
}

/// La programación completa: lista ordenada de piezas y sus ajustes.
public struct Funcion: Codable, Equatable, Sendable {
    public var nombre: String
    public var piezas: [Pieza]
    public var rutaFondo: String?
    public var volumen: Double

    public init(nombre: String = "Función sin título", piezas: [Pieza] = [], rutaFondo: String? = nil, volumen: Double = 1) {
        self.nombre = nombre
        self.piezas = piezas
        self.rutaFondo = rutaFondo
        self.volumen = volumen
    }

    enum CodingKeys: String, CodingKey {
        case nombre, piezas, rutaFondo, volumen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = try c.decodeIfPresent(String.self, forKey: .nombre) ?? "Función sin título"
        piezas = try c.decodeIfPresent([Pieza].self, forKey: .piezas) ?? []
        rutaFondo = try c.decodeIfPresent(String.self, forKey: .rutaFondo)
        volumen = try c.decodeIfPresent(Double.self, forKey: .volumen) ?? 1
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
