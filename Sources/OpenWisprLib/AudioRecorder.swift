import AVFoundation
import CoreAudio
import Foundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var isRecording = false
    private var currentOutputURL: URL?
    var preferredDeviceID: AudioDeviceID?
    var onLevel: ((Float) -> Void)?
    var onChunkReady: ((URL) -> Void)?

    private var chunkTimer: Timer?
    private var chunkIndex = 0
    private var chunkInterval: TimeInterval = 2.0
    private var sessionCapTimer: Timer?
    private var silenceTimer: Timer?
    private var lastLoudTime: Date = Date()
    private var silenceThreshold: Float = 0.02
    private var silenceTimeout: TimeInterval = 3.0
    var onSessionCap: (() -> Void)?
    var onSilenceTimeout: (() -> Void)?

    func prewarm() {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()

        if let deviceID = preferredDeviceID,
           deviceID != AudioDeviceManager.getDefaultInputDeviceID() {
            setInputDevice(deviceID, on: engine)
        }

        _ = engine.inputNode
        engine.prepare()
        audioEngine = engine
    }

    /// Stop and release the engine. Call before changing input device or on shutdown.
    func teardown() {
        if isRecording {
            audioEngine?.inputNode.removeTap(onBus: 0)
            isRecording = false
            currentOutputURL = nil
        }
        audioEngine?.stop()
        audioEngine = nil
    }

    /// Re-prewarm with the current preferredDeviceID. Use after a config change.
    func reload() {
        teardown()
        prewarm()
    }

    func startRecording(to outputURL: URL, streamingChunkSeconds: TimeInterval? = nil, sessionCapSeconds: TimeInterval? = nil, silenceTimeoutSeconds: TimeInterval? = nil) throws {
        guard !isRecording else { return }

        if audioEngine == nil {
            prewarm()
        }

        guard let engine = audioEngine else {
            throw NSError(
                domain: "OpenWispr.AudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Audio engine is not available"]
            )
        }

        chunkIndex = 0
        lastLoudTime = Date()
        if let s = silenceTimeoutSeconds { silenceTimeout = s }

        try engine.start()

        let inputFmt = engine.inputNode.outputFormat(forBus: 0)

        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let file = try AVAudioFile(forWriting: outputURL, settings: settings)
        let converter = AVAudioConverter(from: inputFmt, to: recordingFormat)

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFmt) { [weak self] buffer, _ in
            guard let self = self, let converter = converter else { return }

            let rms = Self.rmsLevel(buffer: buffer)
            self.onLevel?(rms)
            if rms > self.silenceThreshold {
                self.lastLoudTime = Date()
            }

            let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: recordingFormat,
                frameCapacity: AVAudioFrameCount(
                    Double(buffer.frameLength) * 16000.0 / inputFmt.sampleRate
                )
            )!

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil && convertedBuffer.frameLength > 0 {
                try? file.write(from: convertedBuffer)
            }
        }

        currentOutputURL = outputURL
        isRecording = true

        if let interval = streamingChunkSeconds, interval > 0, onChunkReady != nil {
            chunkInterval = interval
            DispatchQueue.main.async { [weak self] in
                self?.scheduleChunkTimer()
            }
        }

        if let cap = sessionCapSeconds, cap > 0 {
            DispatchQueue.main.async { [weak self] in
                self?.sessionCapTimer = Timer.scheduledTimer(withTimeInterval: cap, repeats: false) { _ in
                    self?.onSessionCap?()
                }
            }
        }

        if silenceTimeoutSeconds != nil {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleSilenceTimer()
            }
        }
    }

    private func scheduleChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkInterval, repeats: true) { [weak self] _ in
            self?.emitChunk()
        }
    }

    private func scheduleSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSince(self.lastLoudTime) >= self.silenceTimeout {
                self.silenceTimer?.invalidate()
                self.onSilenceTimeout?()
            }
        }
    }

    private func emitChunk() {
        guard let url = currentOutputURL, FileManager.default.fileExists(atPath: url.path) else { return }
        chunkIndex += 1
        let chunkURL = url.deletingLastPathComponent()
            .appendingPathComponent("chunk-\(chunkIndex)-\(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: chunkURL)
        try? FileManager.default.copyItem(at: url, to: chunkURL)
        onChunkReady?(chunkURL)
    }

    private static func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames { sum += channel[i] * channel[i] }
        return sqrt(sum / Float(frames))
    }

    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        isRecording = false

        chunkTimer?.invalidate()
        chunkTimer = nil
        sessionCapTimer?.invalidate()
        sessionCapTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil

        let url = currentOutputURL
        currentOutputURL = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()

        return url
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) {
        guard let audioUnit = engine.inputNode.audioUnit else {
            print("Warning: could not access audio unit to set input device")
            return
        }

        var devID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            print("Warning: failed to set audio input device (status: \(status))")
        }
    }
}
