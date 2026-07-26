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

        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 1, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        memset(buffer.int16ChannelData![0], 0, frameCount * MemoryLayout<Int16>.size)

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
