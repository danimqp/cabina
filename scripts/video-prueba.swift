// Genera un vídeo H.264 de 5 segundos para la autoprueba. Uso: video-prueba salida.mp4
import AVFoundation
import CoreVideo
import Foundation

let destino = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: destino)

let ancho = 640, alto = 360
let fps: Int32 = 24
let fotogramas = Int(fps) * 5

let escritor = try AVAssetWriter(outputURL: destino, fileType: .mp4)
let entrada = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: ancho,
    AVVideoHeightKey: alto,
])
let adaptador = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: entrada, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: ancho,
    kCVPixelBufferHeightKey as String: alto,
])
escritor.add(entrada)
guard escritor.startWriting() else {
    print("no se pudo empezar: \(String(describing: escritor.error))")
    exit(1)
}
escritor.startSession(atSourceTime: .zero)

for i in 0..<fotogramas {
    while !entrada.isReadyForMoreMediaData { usleep(2000) }
    var creado: CVPixelBuffer?
    CVPixelBufferCreate(nil, ancho, alto, kCVPixelFormatType_32BGRA, nil, &creado)
    guard let buffer = creado else { print("sin buffer"); exit(1) }
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let fila = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<alto {
        for x in 0..<ancho {
            let p = base + y * fila + x * 4
            let franja = (x + i * 5) % ancho < ancho / 2
            p[0] = franja ? 51 : 23     // azul
            p[1] = franja ? 163 : 20    // verde
            p[2] = franja ? 240 : 14    // rojo
            p[3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptador.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
}

entrada.markAsFinished()
let espera = DispatchSemaphore(value: 0)
escritor.finishWriting { espera.signal() }
espera.wait()
if escritor.status == .completed {
    print("vídeo de prueba creado")
} else {
    print("fallo al crear el vídeo: \(String(describing: escritor.error))")
    exit(1)
}
