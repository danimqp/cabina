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
                .frame(minWidth: 1040, minHeight: 700)
                .onAppear {
                    Teclado.instalar(motor: motor)
                    Pruebas.arrancarSiProcede(motor: motor, salida: salida)
                }
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nueva función") { motor.nuevaFuncion() }
                    .keyboardShortcut("n")
                Button("Abrir función…") { motor.abrirFuncion() }
                    .keyboardShortcut("o")
                Button("Guardar función como…") { motor.guardarFuncionComo() }
                    .keyboardShortcut("s")
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
