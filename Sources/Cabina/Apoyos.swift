import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import ImageIO

// MARK: Archivos

/// Resultado de abrir una imagen fuera del hilo principal.
struct ImagenCargada: @unchecked Sendable {
    let imagen: CGImage?
}

enum Archivos {
    /// `true` si la ruta lleva a un archivo normal (no carpeta, dispositivo ni tubería) y, si se indica, no supera el tamaño.
    static func esNormal(_ ruta: String, maximo: Int64? = nil) -> Bool {
        guard !ruta.isEmpty else { return false }
        let real = URL(fileURLWithPath: ruta).resolvingSymlinksInPath().path
        guard let atributos = try? FileManager.default.attributesOfItem(atPath: real),
              atributos[.type] as? FileAttributeType == .typeRegular else { return false }
        if let maximo {
            return ((atributos[.size] as? NSNumber)?.int64Value ?? .max) <= maximo
        }
        return true
    }

    /// Comprueba solo la cabecera de la imagen.
    static func esImagenLegible(_ ruta: String) -> Bool {
        guard esNormal(ruta),
              let fuente = CGImageSourceCreateWithURL(URL(fileURLWithPath: ruta) as CFURL, nil) else { return false }
        return CGImageSourceGetCount(fuente) > 0 && CGImageSourceCopyPropertiesAtIndex(fuente, 0, nil) != nil
    }

    /// Un fotograma del vídeo en la fracción indicada de su duración (0…1), reducido a `lado` píxeles.
    static func fotograma(_ ruta: String, fraccion: Double, lado: CGFloat) async -> (imagen: ImagenCargada, segundo: Double) {
        guard esNormal(ruta) else { return (ImagenCargada(imagen: nil), 0) }
        let recurso = AVURLAsset(url: URL(fileURLWithPath: ruta))
        guard let duracion = try? await recurso.load(.duration), duracion.isNumeric, duracion.seconds > 0 else {
            return (ImagenCargada(imagen: nil), 0)
        }
        let generador = AVAssetImageGenerator(asset: recurso)
        generador.appliesPreferredTrackTransform = true
        generador.maximumSize = CGSize(width: lado, height: lado)
        let holgura = CMTime(seconds: 2, preferredTimescale: 600)
        generador.requestedTimeToleranceBefore = holgura
        generador.requestedTimeToleranceAfter = holgura
        let segundo = duracion.seconds * max(0, min(1, fraccion))
        let resultado = try? await generador.image(at: CMTime(seconds: segundo, preferredTimescale: 600))
        return (ImagenCargada(imagen: resultado?.image), segundo)
    }

    /// Tamaño real, fotogramas por segundo y duración de un vídeo, en una línea.
    static func detalleDeVideo(_ ruta: String) async -> String {
        let recurso = AVURLAsset(url: URL(fileURLWithPath: ruta))
        var partes: [String] = []
        if let pista = try? await recurso.loadTracks(withMediaType: .video).first {
            if let tam = try? await pista.load(.naturalSize), let giro = try? await pista.load(.preferredTransform) {
                let real = tam.applying(giro)
                partes.append("\(Int(abs(real.width).rounded())) × \(Int(abs(real.height).rounded())) píxeles")
            }
            if let fps = try? await pista.load(.nominalFrameRate), fps > 0 {
                partes.append(String(format: "%.4g fps", Double(fps)))
            }
        }
        let sonido = (try? await recurso.loadTracks(withMediaType: .audio)) ?? []
        partes.append(sonido.isEmpty ? "sin sonido" : "con sonido")
        return partes.joined(separator: " · ")
    }

    /// Tamaño en píxeles de una imagen, leyendo solo la cabecera.
    static func detalleDeImagen(_ ruta: String) -> String {
        guard esNormal(ruta),
              let fuente = CGImageSourceCreateWithURL(URL(fileURLWithPath: ruta) as CFURL, nil),
              let datos = CGImageSourceCopyPropertiesAtIndex(fuente, 0, nil) as? [CFString: Any],
              let ancho = datos[kCGImagePropertyPixelWidth] as? Int,
              let alto = datos[kCGImagePropertyPixelHeight] as? Int else { return "Imagen" }
        return "\(ancho) × \(alto) píxeles"
    }

    /// Abre la imagen ya orientada y reducida, como mucho, a 3840 px de lado: suficiente para un proyector 4K.
    static func imagen(_ ruta: String) -> ImagenCargada {
        imagen(ruta, lado: 3840)
    }

    static func imagen(_ ruta: String, lado: Int) -> ImagenCargada {
        guard esNormal(ruta),
              let fuente = CGImageSourceCreateWithURL(URL(fileURLWithPath: ruta) as CFURL, nil) else {
            return ImagenCargada(imagen: nil)
        }
        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: lado,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return ImagenCargada(imagen: CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary))
    }
}

// MARK: Salidas de sonido

struct DispositivoAudio: Identifiable, Hashable {
    let uid: String
    let nombre: String
    var id: String { uid }
}

enum Audio {
    /// Dispositivos por los que puede sonar la película (altavoces, HDMI, interfaz…).
    static func salidas() -> [DispositivoAudio] {
        var direccion = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let sistema = AudioObjectID(kAudioObjectSystemObject)
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sistema, &direccion, 0, nil, &bytes) == noErr, bytes > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sistema, &direccion, 0, nil, &bytes, &ids) == noErr else { return [] }

        var resultado: [DispositivoAudio] = []
        for id in ids {
            var flujos = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var tam: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &flujos, 0, nil, &tam) == noErr, tam > 0 else { continue }
            guard let uid = cadena(id, kAudioDevicePropertyDeviceUID),
                  let nombre = cadena(id, kAudioObjectPropertyName) else { continue }
            resultado.append(DispositivoAudio(uid: uid, nombre: nombre))
        }
        return resultado
    }

    private static func cadena(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var direccion = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var valor: Unmanaged<CFString>?
        var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let estado = withUnsafeMutablePointer(to: &valor) { puntero in
            AudioObjectGetPropertyData(id, &direccion, 0, nil, &tam, puntero)
        }
        guard estado == noErr, let valor else { return nil }
        return valor.takeRetainedValue() as String
    }
}

// MARK: Mensajes de texto

enum Rotulo {
    /// Dibuja un mensaje centrado, en claro sobre negro, a tamaño de proyección.
    static func imagen(_ texto: String, cifrasFijas: Bool = false) -> NSImage {
        let tam = NSSize(width: 1920, height: 1080)
        let dibujo = NSImage(size: tam, flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()

            let parrafo = NSMutableParagraphStyle()
            parrafo.alignment = .center
            parrafo.lineBreakMode = .byWordWrapping
            let color = NSColor(srgbRed: 0.90, green: 0.89, blue: 0.84, alpha: 1)
            let caja = rect.insetBy(dx: 170, dy: 130)
            let opciones: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

            var punto: CGFloat = 170
            var atribuido = NSAttributedString()
            var alto: CGFloat = 0
            while true {
                let base = cifrasFijas
                    ? NSFont.monospacedDigitSystemFont(ofSize: punto, weight: .bold)
                    : NSFont.systemFont(ofSize: punto, weight: .bold)
                let fuente = cifrasFijas
                    ? base
                    : (base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: punto) } ?? base)
                atribuido = NSAttributedString(string: texto, attributes: [
                    .font: fuente, .foregroundColor: color, .paragraphStyle: parrafo,
                ])
                alto = atribuido.boundingRect(
                    with: NSSize(width: caja.width, height: .greatestFiniteMagnitude), options: opciones
                ).height
                if alto <= caja.height || punto <= 40 { break }
                punto -= 10
            }
            atribuido.draw(
                with: NSRect(x: caja.minX, y: caja.midY - alto / 2, width: caja.width, height: alto),
                options: opciones
            )
            return true
        }
        if let cg = dibujo.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSImage(cgImage: cg, size: tam)
        }
        return dibujo
    }
}

// MARK: Atajos globales

/// Atajos que funcionan aunque Cabina no esté en primer plano: ⌃⌥⌘B (negro) y ⌃⌥⌘P (pausa).
@MainActor
enum AtajosGlobales {
    private static weak var motor: Motor?
    private static var instalado = false
    private(set) static var registrados = 0

    static func instalar(motor: Motor) {
        self.motor = motor
        guard !instalado else { return }
        instalado = true

        var tipo = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, evento, _ in
            var id = EventHotKeyID()
            let estado = GetEventParameter(
                evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard estado == noErr else { return estado }
            let numero = id.id
            Task { @MainActor in AtajosGlobales.ejecutar(numero) }
            return noErr
        }, 1, &tipo, nil, nil)

        registrar(tecla: kVK_ANSI_B, numero: 1)
        registrar(tecla: kVK_ANSI_P, numero: 2)
    }

    private static func registrar(tecla: Int, numero: UInt32) {
        var referencia: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4342_4E41), id: numero)
        let estado = RegisterEventHotKey(
            UInt32(tecla), UInt32(cmdKey | optionKey | controlKey), id,
            GetApplicationEventTarget(), 0, &referencia
        )
        if estado == noErr { registrados += 1 }
    }

    static func ejecutar(_ numero: UInt32) {
        guard let motor else { return }
        switch numero {
        case 1: motor.alternarNegro()
        case 2: motor.alternarReproduccion()
        default: break
        }
    }
}
