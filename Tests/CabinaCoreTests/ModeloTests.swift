import XCTest
@testable import CabinaCore

final class ModeloTests: XCTestCase {
    private func funcion(_ nombres: [String]) -> Funcion {
        Funcion(piezas: nombres.map { Pieza(nombre: $0, ruta: "/tmp/\($0).mp4", tipo: .video) })
    }

    private func orden(_ f: Funcion) -> [String] { f.piezas.map(\.nombre) }

    func testTiposPorExtension() {
        XCTAssertEqual(TipoPieza.deArchivo(URL(fileURLWithPath: "/a/corto.MP4")), .video)
        XCTAssertEqual(TipoPieza.deArchivo(URL(fileURLWithPath: "/a/corto.mov")), .video)
        XCTAssertEqual(TipoPieza.deArchivo(URL(fileURLWithPath: "/a/corto.m4v")), .video)
        XCTAssertEqual(TipoPieza.deArchivo(URL(fileURLWithPath: "/a/placa.PNG")), .imagen)
        XCTAssertEqual(TipoPieza.deArchivo(URL(fileURLWithPath: "/a/placa.jpeg")), .imagen)
        XCTAssertNil(TipoPieza.deArchivo(URL(fileURLWithPath: "/a/notas.pdf")))
        XCTAssertNil(TipoPieza.deArchivo(URL(fileURLWithPath: "/a/peli.mkv")))
    }

    func testAgregarDescartaFormatosNoAdmitidos() {
        var f = Funcion()
        let n = f.agregar([
            URL(fileURLWithPath: "/a/Uno.mp4"),
            URL(fileURLWithPath: "/a/notas.txt"),
            URL(fileURLWithPath: "/a/Placa inicial.png"),
        ])
        XCTAssertEqual(n, 2)
        XCTAssertEqual(orden(f), ["Uno", "Placa inicial"])
        XCTAssertEqual(f.piezas[1].tipo, .imagen)
    }

    func testMoverHaciaAbajo() {
        var f = funcion(["A", "B", "C", "D"])
        f.mover(desde: IndexSet(integer: 0), a: 3)
        XCTAssertEqual(orden(f), ["B", "C", "A", "D"])
    }

    func testMoverHaciaArriba() {
        var f = funcion(["A", "B", "C", "D"])
        f.mover(desde: IndexSet(integer: 3), a: 0)
        XCTAssertEqual(orden(f), ["D", "A", "B", "C"])
    }

    func testMoverVariasAlFinal() {
        var f = funcion(["A", "B", "C", "D"])
        f.mover(desde: IndexSet([0, 2]), a: 4)
        XCTAssertEqual(orden(f), ["B", "D", "A", "C"])
    }

    func testMoverIndicesFueraDeRangoNoRompe() {
        var f = funcion(["A", "B"])
        f.mover(desde: IndexSet(integer: 9), a: 0)
        XCTAssertEqual(orden(f), ["A", "B"])
    }

    func testSiguiente() {
        let f = funcion(["A", "B", "C"])
        XCTAssertEqual(f.siguiente(a: nil)?.nombre, "A")
        XCTAssertEqual(f.siguiente(a: f.piezas[0].id)?.nombre, "B")
        XCTAssertNil(f.siguiente(a: f.piezas[2].id))
        XCTAssertEqual(f.siguiente(a: UUID())?.nombre, "A")
        XCTAssertNil(Funcion().siguiente(a: nil))
    }

    func testQuitarYDuracionTotal() {
        var f = funcion(["A", "B"])
        f.piezas[0].duracion = 60
        f.piezas[1].duracion = 30.5
        XCTAssertEqual(f.duracionTotal, 90.5, accuracy: 0.001)
        f.quitar(f.piezas[0].id)
        XCTAssertEqual(orden(f), ["B"])
    }

    func testGuardarYAbrir() throws {
        var f = funcion(["A", "B"])
        f.nombre = "Muestra de noviembre"
        f.rutaFondo = "/tmp/fondo.png"
        f.volumen = 0.4
        let datos = try JSONEncoder().encode(f)
        XCTAssertEqual(try JSONDecoder().decode(Funcion.self, from: datos), f)
    }

    func testAbrirArchivoIncompleto() throws {
        let f = try JSONDecoder().decode(Funcion.self, from: Data("{}".utf8))
        XCTAssertEqual(f.piezas.count, 0)
        XCTAssertEqual(f.volumen, 1)
    }

    func testMensajeDeTexto() throws {
        let m = Pieza.mensaje("Empezamos en 10 minutos\nGracias por venir")
        XCTAssertEqual(m.tipo, .texto)
        XCTAssertEqual(m.nombre, "Empezamos en 10 minutos")
        XCTAssertEqual(m.texto, "Empezamos en 10 minutos\nGracias por venir")
        let copia = try JSONDecoder().decode(Pieza.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(copia, m)
    }

    func testAbrirFuncionDeLaVersionAnterior() throws {
        let antigua = #"{"nombre":"Muestra","volumen":0.8,"piezas":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","nombre":"A","ruta":"/tmp/A.mp4","tipo":"video","duracion":12}]}"#
        let f = try JSONDecoder().decode(Funcion.self, from: Data(antigua.utf8))
        XCTAssertEqual(f.piezas.first?.duracion, 12)
        XCTAssertNil(f.piezas.first?.posicion)
        XCTAssertNil(f.piezas.first?.volumen)
        XCTAssertEqual(f.musica, [])
        XCTAssertEqual(f.volumenMusica, 0.6, accuracy: 0.001)
    }

    func testDuracionPendiente() {
        var f = funcion(["A", "B", "C"])
        f.piezas[0].duracion = 100
        f.piezas[1].duracion = 50
        f.piezas[2].duracion = 25
        XCTAssertEqual(f.duracionPendiente(sinContar: []), 175, accuracy: 0.001)
        XCTAssertEqual(f.duracionPendiente(sinContar: [f.piezas[0].id]), 75, accuracy: 0.001)
        XCTAssertEqual(f.indice(f.piezas[2].id), 2)
        XCTAssertNil(f.indice(nil))
    }

    func testSubtitulos() {
        let srt = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:03,500\r\n<i>Hola</i> a todos\r\n\r\n2\r\n00:01:00,000 --> 00:01:02,000 X1:0\r\n{\\an8}Segunda\r\nlínea\r\n\r\nbasura sin tiempo\r\n"
        let lista = SRT.leer(srt)
        XCTAssertEqual(lista.count, 2)
        XCTAssertEqual(lista[0], Subtitulo(inicio: 1, fin: 3.5, texto: "Hola a todos"))
        XCTAssertEqual(lista[1].texto, "Segunda\nlínea")
        XCTAssertEqual(lista[1].inicio, 60, accuracy: 0.001)
        XCTAssertEqual(SRT.texto(en: 0.5, de: lista), "")
        XCTAssertEqual(SRT.texto(en: 2, de: lista), "Hola a todos")
        XCTAssertEqual(SRT.texto(en: 3.5, de: lista), "")
        XCTAssertEqual(SRT.texto(en: 61, de: lista), "Segunda\nlínea")
        XCTAssertEqual(SRT.leer("esto no es un srt").count, 0)
        XCTAssertEqual(SRT.leer("").count, 0)
    }

    func testTextoDeTiempo() {
        XCTAssertEqual(Tiempo.texto(0), "00:00")
        XCTAssertEqual(Tiempo.texto(75.9), "01:15")
        XCTAssertEqual(Tiempo.texto(3725), "1:02:05")
        XCTAssertEqual(Tiempo.texto(-4), "00:00")
        XCTAssertEqual(Tiempo.texto(.nan), "00:00")
    }
}
