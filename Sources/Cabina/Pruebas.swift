import CabinaCore
import Foundation

/// Autoprueba para la compilación automática: carga una carpeta, proyecta y deja un informe.
/// Solo se activa con las variables CABINA_PRUEBA (carpeta) y CABINA_INFORME (archivo).
/// Las líneas «CAPTURA nombre» piden al script una captura de pantalla en ese momento.
@MainActor
enum Pruebas {
    private static var hecho = false
    private static var lineas: [String] = []

    static func arrancarSiProcede(motor: Motor, salida: Salida) {
        let entorno = ProcessInfo.processInfo.environment
        guard !hecho, let carpeta = entorno["CABINA_PRUEBA"], let informe = entorno["CABINA_INFORME"] else { return }
        hecho = true

        Task { @MainActor in
            @MainActor func escribir(_ linea: String) {
                lineas.append(linea)
                try? lineas.joined(separator: "\n").appending("\n")
                    .write(toFile: informe, atomically: true, encoding: .utf8)
            }
            @MainActor func anotar(_ correcto: Bool, _ texto: String) {
                escribir((correcto ? "OK    " : "FALLO ") + texto)
            }
            @MainActor func esperar(_ segundos: Double) async {
                try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
            }
            @MainActor func capturar(_ nombre: String) async {
                escribir("CAPTURA " + nombre)
                await esperar(1.6)
            }

            let base = URL(fileURLWithPath: carpeta)
            let todos = ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [])
            let audios = todos.filter { $0.pathExtension.lowercased() == "wav" }
            let archivos = todos.filter { $0.pathExtension.lowercased() != "wav" }
            let agregadas = motor.agregar(archivos)
            anotar(agregadas >= 2, "lista: \(agregadas) piezas agregadas de \(archivos.count) archivos")
            anotar(AtajosGlobales.registrados == 2, "atajos globales registrados: \(AtajosGlobales.registrados) de 2")
            anotar(true, "salidas de sonido detectadas: \(motor.dispositivos.map(\.nombre))")

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

            // Comprobar la función
            motor.comprobar(avisar: true)
            await esperar(1.5)
            anotar(!motor.comprobando && motor.problemas[imagen.id] == nil && motor.problemas[video.id]?.grave != true,
                   "comprobación: \(motor.nota ?? motor.aviso ?? "sin resultado")")

            // Vídeo, negro y lista
            motor.lanzar(video.id)
            await esperar(2.5)
            anotar(motor.esVideo && motor.reproduciendo && motor.tiempo > 1,
                   "vídeo en marcha: tiempo \(motor.tiempo) de \(motor.duracion)")
            anotar(motor.fotogramaPrevia() != nil || motor.tiempo > 1, "la vista previa recibe fotogramas")
            await capturar("1-video")

            motor.alternarNegro()
            await esperar(0.6)
            let congelado = motor.tiempo
            anotar(motor.negro && !motor.reproduciendo, "negro activo y vídeo detenido en \(congelado)")
            await esperar(0.6)
            motor.alternarNegro()
            await esperar(0.6)
            anotar(!motor.negro && motor.reproduciendo && motor.tiempo >= congelado,
                   "al quitar negro continúa desde \(congelado): ahora \(motor.tiempo)")

            motor.funcion.mover(desde: IndexSet(integer: 0), a: motor.funcion.piezas.count)
            anotar(motor.esVideo && motor.reproduciendo, "reordenar la lista no interrumpe la proyección")

            // Volumen propio del vídeo
            motor.fijarVolumen(0.5)
            anotar(motor.funcion.pieza(video.id)?.volumen == 0.5 && motor.funcion.volumen == 1,
                   "el volumen cambiado durante el vídeo se guarda en ese vídeo, no en el general")

            // Mensaje rápido que corta el vídeo; el punto queda guardado
            while motor.tiempo < 7, motor.esVideo { await esperar(0.3) }
            let corte = motor.tiempo
            motor.mostrarMensaje("Empezamos en 10 minutos")
            let guardado = motor.funcion.pieza(video.id)?.posicion ?? -1
            anotar(motor.esImagen && motor.esMensaje && motor.imagenVisible != nil, "mensaje rápido en pantalla")
            anotar(abs(guardado - corte) < 1.5, "punto del corte guardado: \(guardado) (cortado en \(corte))")
            anotar(motor.volumenActual == 1, "sin vídeo en pantalla el volumen vuelve al general")
            await capturar("2-mensaje")

            // Música de espera
            if let audio = audios.first {
                motor.fijarMusica([audio])
                motor.encenderMusica()
                await esperar(2)
                anotar(motor.musicaEncendida && motor.musicaSonando && motor.musica.volume > 0.3,
                       "música de espera sonando: «\(motor.pistaMusica)» a volumen \(motor.musica.volume)")
            } else {
                anotar(false, "falta el audio de prueba")
            }

            // Seguir donde se cortó: la música se calla
            motor.pedirLanzar(video.id)
            await esperar(2.2)
            anotar(motor.esVideo && motor.tiempo >= guardado && motor.tiempo < guardado + 4,
                   "el vídeo sigue desde el corte: \(motor.tiempo) (guardado \(guardado))")
            anotar(!motor.musicaSonando && motor.musicaEncendida, "la música se calla durante el vídeo")
            anotar(abs(Double(motor.player.volume) - 0.5) < 0.01, "el vídeo recupera su volumen propio: \(motor.player.volume)")

            // Final natural: vuelve al fondo, olvida el punto y vuelve la música
            var espera = 0.0
            while motor.esVideo, espera < 12 { await esperar(0.3); espera += 0.3 }
            anotar(motor.contenido == .fondo && !motor.reproduciendo,
                   "al terminar el vídeo vuelve al fondo (contenido: \(motor.contenido))")
            anotar(motor.pasadas.contains(video.id), "el vídeo queda marcado como ya proyectado")
            anotar(motor.funcion.pieza(video.id)?.posicion == nil, "al terminar entero se olvida el punto guardado")
            await esperar(2)
            anotar(motor.musicaSonando, "la música vuelve sola al terminar el vídeo")
            motor.apagarMusica()
            await esperar(2.5)
            anotar(!motor.musicaSonando && !motor.musicaEncendida, "la música se apaga al pararla")

            // Imagen fija
            motor.lanzar(imagen.id)
            await esperar(1)
            anotar(motor.esImagen && !motor.esMensaje && motor.imagenVisible != nil, "imagen en pantalla")
            await capturar("3-imagen")
            await esperar(1.5)
            anotar(motor.esImagen, "la imagen sigue en pantalla sin avanzar sola")
            motor.volverAlFondo()
            anotar(motor.contenido == .fondo, "volver al fondo retira la imagen")

            // Mensaje guardado en la lista
            motor.agregarMensaje("Conversatorio con el equipo")
            let mensaje = motor.funcion.piezas.last
            anotar(mensaje?.tipo == .texto, "mensaje añadido a la lista")
            if let mensaje {
                motor.lanzar(mensaje.id)
                anotar(motor.esMensaje && motor.idEnPantalla == mensaje.id, "mensaje de la lista en pantalla")
            }

            // Deja la ventana de control a la vista para la captura
            salida.cerrar()
            anotar(!salida.abierta, "salida cerrada")
            motor.seleccion = imagen.id
            motor.lanzar(video.id)
            await esperar(1.5)
            anotar(motor.esVideo, "ventana de control con vídeo en marcha")
            await capturar("4-control")
            anotar(true, "FIN")
        }
    }
}
