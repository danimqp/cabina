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

    func testTextoDeTiempo() {
        XCTAssertEqual(Tiempo.texto(0), "00:00")
        XCTAssertEqual(Tiempo.texto(75.9), "01:15")
        XCTAssertEqual(Tiempo.texto(3725), "1:02:05")
        XCTAssertEqual(Tiempo.texto(-4), "00:00")
        XCTAssertEqual(Tiempo.texto(.nan), "00:00")
    }
}
