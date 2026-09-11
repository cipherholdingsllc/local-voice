import AVFoundation
import Foundation

/// Model warm-keep (#6): preload STT engine at boot via silent warmup transcribe.
enum WhisperWarmKeeper {
    static func warmup(transcriber: Transcriber) {
        guard let url = try? makeSilentWAV(durationSeconds: 0.25) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try? transcriber.transcribe(audioURL: url)
        fputs("WhisperWarmKeeper: model warmed\n", stderr)
    }

    private static func makeSilentWAV(durationSeconds: Double) throws -> URL {
        let sampleRate = 16000
        let frameCount = Int(durationSeconds * Double(sampleRate))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-flow-warmup-\(UUID().uuidString).wav")

        let dataSize = UInt32(frameCount * MemoryLayout<Int16>.size)
        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            wav.append(Data(bytes: &little, count: MemoryLayout<T>.size))
        }
        wav.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * MemoryLayout<Int16>.size))
        append(UInt16(MemoryLayout<Int16>.size))
        append(UInt16(16))
        wav.append(contentsOf: Array("data".utf8))
        append(dataSize)
        wav.append(Data(count: Int(dataSize)))

        try wav.write(to: url, options: .atomic)
        return url
    }
}
