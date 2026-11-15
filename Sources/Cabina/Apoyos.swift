import AppKit
import Carbon.HIToolbox
import CoreAudio

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
    static func imagen(_ texto: String) -> NSImage {
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
                let base = NSFont.systemFont(ofSize: punto, weight: .bold)
                let fuente = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: punto) } ?? base
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
