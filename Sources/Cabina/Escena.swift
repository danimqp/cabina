import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Dibuja lo que ve el público: fondo negro, imagen, vídeo y la cortina de negro.
/// Se usa tal cual en la ventana de salida y, en modo `previa`, en la miniatura del operador.
final class EscenaView: NSView {
    enum Modo {
        case salida
        case previa
    }

    var ocultaCursor = false

    private let motor: Motor
    private let modo: Modo
    private let capaImagen = CALayer()
    private let capaVideo: CALayer
    private let capaNegro = CALayer()
    private var suscripcion: AnyCancellable?
    private var reloj: Timer?
    private var cursorOculto = false
    private var mostrandoVideo = false

    init(motor: Motor, modo: Modo) {
        self.motor = motor
        self.modo = modo
        switch modo {
        case .salida:
            let capa = AVPlayerLayer(player: motor.player)
            capa.videoGravity = .resizeAspect
            capaVideo = capa
        case .previa:
            let capa = CALayer()
            capa.contentsGravity = .resizeAspect
            capaVideo = capa
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 360))

        let raiz = CALayer()
        raiz.backgroundColor = NSColor.black.cgColor
        layer = raiz
        wantsLayer = true

        capaImagen.contentsGravity = .resizeAspect
        capaNegro.backgroundColor = NSColor.black.cgColor
        capaNegro.opacity = 0
        capaVideo.isHidden = true
        for capa in [capaImagen, capaVideo, capaNegro] {
            capa.frame = bounds
            capa.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            raiz.addSublayer(capa)
        }

        suscripcion = Publishers.CombineLatest3(motor.$contenido, motor.$imagenVisible, motor.$negro)
            .sink { [weak self] contenido, imagen, negro in
                self?.aplicar(contenido: contenido, imagen: imagen, negro: negro)
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EscenaView no se crea desde un archivo de interfaz")
    }

    private func aplicar(contenido: Contenido, imagen: NSImage?, negro: Bool) {
        var esVideo = false
        if case .video = contenido { esVideo = true }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if esVideo != mostrandoVideo, modo == .previa {
            capaVideo.contents = nil
        }
        mostrandoVideo = esVideo
        capaVideo.isHidden = !esVideo
        capaImagen.isHidden = esVideo
        capaImagen.contents = esVideo ? nil : imagen
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        capaNegro.opacity = negro ? 1 : 0
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for capa in [capaImagen, capaVideo, capaNegro] {
            capa.frame = bounds
        }
        CATransaction.commit()
    }

    // MARK: Vista previa

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reloj?.invalidate()
        reloj = nil
        if window == nil {
            mostrarCursor()
            return
        }
        guard modo == .previa else { return }
        reloj = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refrescarPrevia() }
        }
    }

    private func refrescarPrevia() {
        guard mostrandoVideo, let fotograma = motor.fotogramaPrevia() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capaVideo.contents = fotograma
        CATransaction.commit()
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        guard ocultaCursor else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard ocultaCursor, !cursorOculto else { return }
        NSCursor.hide()
        cursorOculto = true
    }

    override func mouseExited(with event: NSEvent) {
        mostrarCursor()
    }

    func mostrarCursor() {
        guard cursorOculto else { return }
        NSCursor.unhide()
        cursorOculto = false
    }
}

/// Miniatura de lo que ve el público, para el panel del operador.
struct VistaPrevia: NSViewRepresentable {
    let motor: Motor

    func makeNSView(context: Context) -> EscenaView {
        EscenaView(motor: motor, modo: .previa)
    }

    func updateNSView(_ nsView: EscenaView, context: Context) {}
}
