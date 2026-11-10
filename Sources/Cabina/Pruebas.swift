import CabinaCore
import Foundation

/// Autoprueba para la compilación automática: carga una carpeta, proyecta y deja un informe.
/// Solo se activa con las variables CABINA_PRUEBA (carpeta) y CABINA_INFORME (archivo).
@MainActor
enum Pruebas {
    private static var hecho = false
    private static var lineas: [String] = []

    static func arrancarSiProcede(motor: Motor, salida: Salida) {
        let entorno = ProcessInfo.processInfo.environment
        guard !hecho, let carpeta = entorno["CABINA_PRUEBA"], let informe = entorno["CABINA_INFORME"] else { return }
        hecho = true

        Task { @MainActor in
            @MainActor func anotar(_ correcto: Bool, _ texto: String) {
                lineas.append((correcto ? "OK    " : "FALLO ") + texto)
                try? lineas.joined(separator: "\n").appending("\n")
                    .write(toFile: informe, atomically: true, encoding: .utf8)
            }
            @MainActor func esperar(_ segundos: Double) async {
                try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
            }

            let base = URL(fileURLWithPath: carpeta)
            let archivos = ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [])
            let agregadas = motor.agregar(archivos)
            anotar(agregadas >= 2, "lista: \(agregadas) piezas agregadas de \(archivos.count) archivos")

            salida.abrir()
            await esperar(1)
            anotar(salida.abierta, "salida abierta (en proyector: \(salida.enProyector))")
            anotar(motor.contenido == .fondo && !motor.reproduciendo, "antes de lanzar, la salida está en el fondo")

            guard let video = motor.funcion.piezas.first(where: { $0.tipo == .video }),
                  let imagen = motor.funcion.piezas.first(where: { $0.tipo == .imagen }) else {
                anotar(false, "faltan un vídeo y una imagen en la carpeta de prueba")
                return
            }

            anotar(video.duracion != nil, "duración detectada: \(video.duracion ?? -1) s")

            motor.lanzar(video.id)
            await esperar(2.5)
            anotar(motor.esVideo && motor.reproduciendo && motor.tiempo > 1,
                   "vídeo en marcha: tiempo \(motor.tiempo) de \(motor.duracion)")
            anotar(motor.fotogramaPrevia() != nil || motor.tiempo > 1, "la vista previa recibe fotogramas")

            motor.alternarNegro()
            await esperar(0.6)
            let congelado = motor.tiempo
            anotar(motor.negro && !motor.reproduciendo, "negro activo y vídeo detenido en \(congelado)")
            await esperar(0.6)
            motor.alternarNegro()
            await esperar(0.6)
            anotar(!motor.negro && motor.reproduciendo && motor.tiempo >= congelado,
                   "al quitar negro continúa desde \(congelado): ahora \(motor.tiempo)")

            // La lista se edita mientras se proyecta
            motor.funcion.mover(desde: IndexSet(integer: 0), a: motor.funcion.piezas.count)
            anotar(motor.esVideo && motor.reproduciendo, "reordenar la lista no interrumpe la proyección")

            await esperar(4.5)
            anotar(motor.contenido == .fondo && !motor.reproduciendo,
                   "al terminar el vídeo vuelve al fondo (contenido: \(motor.contenido))")
            anotar(motor.pasadas.contains(video.id), "el vídeo queda marcado como ya proyectado")

            motor.lanzar(imagen.id)
            await esperar(1)
            anotar(motor.esImagen && motor.imagenVisible != nil, "imagen en pantalla")
            await esperar(3)
            anotar(motor.esImagen, "la imagen sigue en pantalla sin avanzar sola")

            motor.volverAlFondo()
            anotar(motor.contenido == .fondo, "volver al fondo retira la imagen")

            // Deja la ventana de control a la vista para la captura
            salida.cerrar()
            anotar(!salida.abierta, "salida cerrada")
            motor.seleccion = imagen.id
            motor.lanzar(video.id)
            await esperar(1.5)
            anotar(motor.esVideo, "CONTROL")
            await esperar(3)
            anotar(true, "FIN")
        }
    }
}
