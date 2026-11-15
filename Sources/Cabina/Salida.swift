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

    /// La salida abierta en este momento, para que la app pueda avisar antes de cerrarse.
    private(set) static weak var actual: Salida?

    func alternar() {
        if abierta { cerrarConAviso() } else { abrir() }
    }

    /// Cierra la salida; si el público está viendo algo en el proyector, pide confirmación antes.
    func cerrarConAviso() {
        guard abierta else { return }
        if enProyector, motor.idEnPantalla != nil, !motor.negro {
            let alerta = NSAlert()
            alerta.messageText = "¿Cerrar la salida?"
            alerta.informativeText = "El público dejará de ver la proyección y verá el escritorio del ordenador."
            alerta.addButton(withTitle: "Cerrar la salida")
            alerta.addButton(withTitle: "Seguir proyectando")
            guard alerta.runModal() == .alertFirstButtonReturn else { return }
        }
        cerrar()
    }

    func abrir() {
        guard !abierta else { return }
        montarVentana()
        abierta = true
        Self.actual = self
        protegerVentanaDeControl(true)
        if !enProyector, CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0 {
            motor.aviso = "Las pantallas están duplicadas: el público vería también los controles. En Ajustes del Sistema > Pantallas, elige «Pantalla ampliada» y vuelve a abrir la salida."
        }
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
        protegerVentanaDeControl(false)
        if let actividad {
            ProcessInfo.processInfo.endActivity(actividad)
            self.actividad = nil
        }
    }

    // MARK: Ventana

    private var ventanaDeControl: NSWindow? {
        NSApp.windows.first { $0 !== ventana && $0.canBecomeMain && !($0 is NSPanel) }
    }

    /// Con la salida abierta, la ventana de control no se puede cerrar por error (botón rojo o ⌘W).
    private func protegerVentanaDeControl(_ proteger: Bool) {
        ventanaDeControl?.standardWindowButton(.closeButton)?.isEnabled = !proteger
    }

    private static func esIntegrada(_ pantalla: NSScreen) -> Bool {
        guard let numero = pantalla.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(numero.uint32Value) != 0
    }

    /// La pantalla que no es la del operador, si existe.
    private func pantallaProyector() -> NSScreen? {
        let pantallas = NSScreen.screens
        guard pantallas.count > 1 else { return nil }
        // Portátil con una pantalla externa: el proyector es siempre la externa,
        // esté donde esté la ventana de control.
        let externas = pantallas.filter { !Self.esIntegrada($0) }
        if externas.count == 1, pantallas.count == 2 {
            return externas[0]
        }
        let control = ventanaDeControl?.screen ?? NSScreen.main
        return pantallas.first { $0 != control }
    }

    /// Si la ventana de control quedó en la pantalla del proyector, la devuelve a la del operador.
    private func apartarControl(de proyector: NSScreen) {
        guard let control = ventanaDeControl, control.screen == proyector,
              let destino = NSScreen.screens.first(where: { $0 != proyector }) else { return }
        let marco = destino.visibleFrame
        let ancho = min(control.frame.width, marco.width)
        let alto = min(control.frame.height, marco.height)
        control.setFrame(
            NSRect(x: marco.midX - ancho / 2, y: marco.midY - alto / 2, width: ancho, height: alto),
            display: true
        )
    }

    private func montarVentana() {
        let nueva: NSWindow
        let vista = EscenaView(motor: motor, modo: .salida)

        if let proyector = pantallaProyector() {
            apartarControl(de: proyector)
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
        motor.actualizarDispositivos()
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
        protegerVentanaDeControl(false)
        if let actividad {
            ProcessInfo.processInfo.endActivity(actividad)
            self.actividad = nil
        }
    }
}
