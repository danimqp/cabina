import AppKit
import Combine

/// Gestiona la ventana del público: a pantalla completa en el proyector o, si no hay, en una ventana de prueba.
@MainActor
final class Salida: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var abierta = false
    @Published private(set) var enProyector = false

    private let motor: Motor
    private var ventana: NSWindow?
    private var escena: EscenaView?
    private var actividad: NSObjectProtocol?
    private var observador: NSObjectProtocol?
    private var cerrandoPorCodigo = false

    init(motor: Motor) {
        self.motor = motor
        super.init()
        observador = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pantallasCambiaron() }
        }
    }

    func alternar() {
        if abierta { cerrar() } else { abrir() }
    }

    func abrir() {
        guard !abierta else { return }
        montarVentana()
        abierta = true
        if actividad == nil {
            actividad = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
                reason: "Cabina está proyectando"
            )
        }
    }

    func cerrar() {
        guard abierta else { return }
        desmontarVentana()
        abierta = false
        enProyector = false
        if let actividad {
            ProcessInfo.processInfo.endActivity(actividad)
            self.actividad = nil
        }
    }

    // MARK: Ventana

    /// La pantalla que no es la del operador, si existe.
    private func pantallaProyector() -> NSScreen? {
        let control = NSApp.windows.first { $0 !== ventana && $0.isVisible && $0.canBecomeMain }?.screen
            ?? NSScreen.main
        return NSScreen.screens.first { $0 != control }
    }

    private func montarVentana() {
        let nueva: NSWindow
        let vista = EscenaView(motor: motor, modo: .salida)

        if let proyector = pantallaProyector() {
            nueva = NSWindow(
                contentRect: proyector.frame, styleMask: [.borderless],
                backing: .buffered, defer: false
            )
            nueva.level = .screenSaver
            nueva.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            nueva.hasShadow = false
            nueva.setFrame(proyector.frame, display: true)
            vista.ocultaCursor = true
            enProyector = true
        } else {
            nueva = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            nueva.title = "Salida de Cabina"
            nueva.center()
            enProyector = false
        }

        nueva.isReleasedWhenClosed = false
        nueva.hidesOnDeactivate = false
        nueva.backgroundColor = .black
        nueva.contentView = vista
        nueva.delegate = self
        nueva.orderFrontRegardless()

        ventana = nueva
        escena = vista
    }

    private func desmontarVentana() {
        escena?.mostrarCursor()
        cerrandoPorCodigo = true
        ventana?.delegate = nil
        ventana?.close()
        cerrandoPorCodigo = false
        ventana = nil
        escena = nil
    }

    /// Si se conecta o desconecta el proyector, recoloca la salida sin tocar la reproducción.
    private func pantallasCambiaron() {
        guard abierta else { return }
        let proyector = pantallaProyector()
        let debeEstarEnProyector = proyector != nil
        if debeEstarEnProyector == enProyector {
            if let proyector, let ventana, ventana.frame != proyector.frame {
                ventana.setFrame(proyector.frame, display: true)
            }
            return
        }
        desmontarVentana()
        montarVentana()
    }

    // El operador cerró a mano la ventana de prueba.
    func windowWillClose(_ notification: Notification) {
        guard !cerrandoPorCodigo else { return }
        ventana?.delegate = nil
        ventana = nil
        escena = nil
        abierta = false
        enProyector = false
        if let actividad {
            ProcessInfo.processInfo.endActivity(actividad)
            self.actividad = nil
        }
    }
}
