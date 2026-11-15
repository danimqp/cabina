import AppKit
import SwiftUI

@main
struct CabinaApp: App {
    @StateObject private var motor: Motor
    @StateObject private var salida: Salida

    init() {
        let motor = Motor()
        _motor = StateObject(wrappedValue: motor)
        _salida = StateObject(wrappedValue: Salida(motor: motor))
    }

    var body: some Scene {
        Window("Cabina", id: "control") {
            VistaControl()
                .environmentObject(motor)
                .environmentObject(salida)
                .preferredColorScheme(.dark)
                .tint(Paleta.ambar)
                .frame(minWidth: 980, minHeight: 720)
                .onAppear {
                    Teclado.instalar(motor: motor)
                    AtajosGlobales.instalar(motor: motor)
                    MiniControl.instalar(motor: motor, salida: salida)
                    Pruebas.arrancarSiProcede(motor: motor, salida: salida)
                }
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Acerca de Cabina") { Creditos.mostrarAcercaDe() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Nueva función") { motor.nuevaFuncion() }
                    .keyboardShortcut("n")
                Button("Abrir función…") { motor.abrirFuncion() }
                    .keyboardShortcut("o")
                Button("Guardar función como…") { motor.guardarFuncionComo() }
                    .keyboardShortcut("s")
                Button("Reunir archivos en una carpeta…") { motor.reunirArchivos() }
                    .disabled(motor.funcion.piezas.isEmpty || motor.copiando)
                Divider()
                Button("Añadir archivos…") { motor.pedirArchivos() }
                    .keyboardShortcut("i")
            }
            CommandMenu("Proyección") {
                Button(salida.abierta ? "Cerrar salida" : "Abrir salida") { salida.alternar() }
                    .keyboardShortcut("p")
                Divider()
                Button("Lanzar la pieza seleccionada") { motor.lanzarSeleccionada() }
                    .keyboardShortcut(.return)
                    .disabled(motor.seleccion == nil)
                Button("Lanzar la siguiente") { motor.lanzarSiguiente() }
                    .keyboardShortcut(.rightArrow)
                    .disabled(motor.siguiente == nil)
                Button(motor.reproduciendo ? "Pausar" : "Reanudar") { motor.alternarReproduccion() }
                    .disabled(!motor.esVideo)
                Button("Volver al fondo") { motor.volverAlFondo() }
                    .keyboardShortcut(".")
                Divider()
                Button(motor.negro ? "Quitar negro" : "Negro") { motor.alternarNegro() }
                    .keyboardShortcut("b")
                Divider()
                Button(motor.musicaEncendida ? "Parar la música de espera" : "Poner la música de espera") {
                    motor.alternarMusica()
                }
                Button("Elegir la música de espera…") { motor.pedirMusica() }
                Picker("Salida de sonido", selection: Binding(
                    get: { motor.salidaAudio ?? "" },
                    set: { motor.elegirSalidaAudio($0.isEmpty ? nil : $0) }
                )) {
                    Text("Salida del sistema").tag("")
                    ForEach(motor.dispositivos) { dispositivo in
                        Text(dispositivo.nombre).tag(dispositivo.uid)
                    }
                }
                Divider()
                Button("Comprobar la función") { motor.comprobar(avisar: true) }
                    .disabled(motor.funcion.piezas.isEmpty)
                Divider()
                Text("Desde cualquier otra app: ⌃⌥⌘B negro · ⌃⌥⌘P pausa")
            }
        }
    }
}

/// Barra espaciadora para pausar o reanudar, salvo cuando se está escribiendo en un campo de texto.
@MainActor
enum Teclado {
    private static var monitor: Any?

    static func instalar(motor: Motor) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak motor] evento in
            let consumido: Bool = MainActor.assumeIsolated {
                guard let motor, evento.keyCode == 49 else { return false }
                let modificadores = evento.modifierFlags.intersection([.command, .option, .control])
                guard modificadores.isEmpty else { return false }
                if NSApp.keyWindow?.firstResponder is NSText { return false }
                guard motor.esVideo else { return false }
                motor.alternarReproduccion()
                return true
            }
            return consumido ? nil : evento
        }
    }
}

extension Creditos {
    @MainActor
    static func mostrarAcercaDe() {
        let parrafo = NSMutableParagraphStyle()
        parrafo.alignment = .center
        let creditos = NSMutableAttributedString(
            string: "Proyección de cortometrajes para muestras, cineclubes y cine comunitario.\n\nApp desarrollada por ",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: parrafo]
        )
        var enlace: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .paragraphStyle: parrafo]
        if let web = Marca.web { enlace[.link] = web }
        creditos.append(NSAttributedString(string: "Muyuna.org", attributes: enlace))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: creditos])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Panel flotante que aparece al pasar a otra app con la salida abierta, y se esconde al volver.
@MainActor
enum MiniControl {
    private static var panel: NSPanel?
    private static weak var motor: Motor?
    private static weak var salida: Salida?
    private static var observadores: [NSObjectProtocol] = []

    static func instalar(motor: Motor, salida: Salida) {
        guard observadores.isEmpty else { return }
        self.motor = motor
        self.salida = salida
        let centro = NotificationCenter.default
        observadores.append(centro.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { mostrar() }
        })
        observadores.append(centro.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ocultar() }
        })
    }

    static func mostrar() {
        guard let motor, let salida, salida.abierta else { return }
        if panel == nil {
            let nuevo = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 330, height: 70),
                styleMask: [.nonactivatingPanel, .titled, .utilityWindow, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            nuevo.title = "Cabina"
            nuevo.titleVisibility = .hidden
            nuevo.titlebarAppearsTransparent = true
            nuevo.isFloatingPanel = true
            nuevo.level = .floating
            nuevo.hidesOnDeactivate = false
            nuevo.becomesKeyOnlyIfNeeded = true
            nuevo.isMovableByWindowBackground = true
            nuevo.isReleasedWhenClosed = false
            nuevo.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let vista = NSHostingView(rootView: VistaMini().environmentObject(motor))
            nuevo.contentView = vista
            nuevo.setContentSize(vista.fittingSize)
            let control = NSApp.windows.first { $0.canBecomeMain && $0.title == "Cabina" }?.screen ?? NSScreen.main
            if let marco = control?.visibleFrame {
                nuevo.setFrameOrigin(NSPoint(x: marco.maxX - nuevo.frame.width - 20, y: marco.minY + 20))
            }
            panel = nuevo
        }
        panel?.orderFrontRegardless()
    }

    static func ocultar() {
        panel?.orderOut(nil)
    }

    static var visible: Bool { panel?.isVisible ?? false }
}
