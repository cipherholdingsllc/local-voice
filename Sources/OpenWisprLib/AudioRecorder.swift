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

    private let chunkQueue = DispatchQueue(
        label: "local-voice.audio-chunks",
        qos: .userInitiated
    )
    private var chunkIndex = 0
    private var streamingChunker: StreamingAudioChunker?
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
        let streamCallback = onChunkReady
        let streamPreview = streamingChunkSeconds.flatMap {
            interval -> StreamingAudioChunker? in
            guard interval > 0, streamCallback != nil else { return nil }
            return StreamingAudioChunker(
                sampleRate: recordingFormat.sampleRate,
                chunkSeconds: interval,
                overlapSeconds: 0.25
            )
        }
        let streamPreviewEnabled = streamPreview != nil
        chunkQueue.sync {
            chunkIndex = 0
            streamingChunker = streamPreview
        }

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
                if streamPreviewEnabled,
                   let streamCallback,
                   let channel = convertedBuffer.floatChannelData?[0] {
                    let samples = Array(
                        UnsafeBufferPointer(
                            start: channel,
                            count: Int(convertedBuffer.frameLength)
                        )
                    )
                    self.enqueueStreamingSamples(
                        samples,
                        outputURL: outputURL,
                        onChunkReady: streamCallback
                    )
                }
            }
        }

        currentOutputURL = outputURL
        isRecording = true

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

    private func enqueueStreamingSamples(
        _ samples: [Float],
        outputURL: URL,
        onChunkReady: @escaping (URL) -> Void
    ) {
        chunkQueue.async { [weak self] in
            guard
                let self,
                var chunker = self.streamingChunker
            else { return }

            let chunks = chunker.append(samples)
            self.streamingChunker = chunker
            for samples in chunks {
                self.chunkIndex += 1
                let chunkURL = outputURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        "chunk-\(self.chunkIndex)-\(outputURL.lastPathComponent)"
                    )
                do {
                    try StreamingChunkWriter.write(
                        samples: samples,
                        sampleRate: chunker.sampleRate,
                        destinationURL: chunkURL
                    )
                    onChunkReady(chunkURL)
                } catch {
                    try? FileManager.default.removeItem(at: chunkURL)
                    fputs(
                        "Streaming preview chunk failed: \(error.localizedDescription)\n",
                        stderr
                    )
                }
            }
        }
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

struct StreamingAudioChunker {
    let sampleRate: Double
    let chunkFrameCount: Int
    let overlapFrameCount: Int

    private var pending: [Float] = []
    private var previousTail: [Float] = []

    init(
        sampleRate: Double,
        chunkSeconds: TimeInterval,
        overlapSeconds: TimeInterval
    ) {
        self.sampleRate = sampleRate
        chunkFrameCount = max(
            1,
            Int((sampleRate * chunkSeconds).rounded())
        )
        overlapFrameCount = min(
            chunkFrameCount,
            max(0, Int((sampleRate * overlapSeconds).rounded()))
        )
        pending.reserveCapacity(chunkFrameCount * 2)
        previousTail.reserveCapacity(overlapFrameCount)
    }

    mutating func append(_ samples: [Float]) -> [[Float]] {
        guard !samples.isEmpty else { return [] }
        pending.append(contentsOf: samples)

        var ready: [[Float]] = []
        while pending.count >= chunkFrameCount {
            let body = Array(pending.prefix(chunkFrameCount))
            pending.removeFirst(chunkFrameCount)

            var output = previousTail
            output.reserveCapacity(
                previousTail.count + body.count
            )
            output.append(contentsOf: body)
            ready.append(output)

            previousTail = Array(body.suffix(overlapFrameCount))
        }
        return ready
    }
}

enum StreamingChunkWriter {
    static func write(
        samples: [Float],
        sampleRate: Double,
        destinationURL: URL
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let destination = try AVAudioFile(
            forWriting: destinationURL,
            settings: settings
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: destination.processingFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw StreamingChunkError.bufferUnavailable
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else {
            throw StreamingChunkError.bufferUnavailable
        }
        samples.withUnsafeBufferPointer { source in
            guard let sourceBase = source.baseAddress else { return }
            channel.update(
                from: sourceBase,
                count: samples.count
            )
        }
        try destination.write(from: buffer)
    }
}

enum StreamingChunkError: LocalizedError {
    case bufferUnavailable

    var errorDescription: String? {
        "Could not allocate the incremental audio buffer"
    }
}

enum StreamingTranscriptAssembler {
    static func merge(existing: String, incoming: String) -> String {
        let current = existing.split(whereSeparator: \.isWhitespace).map(String.init)
        let next = incoming.split(whereSeparator: \.isWhitespace).map(String.init)

        guard !next.isEmpty else { return existing }
        guard !current.isEmpty else { return incoming }

        let currentKeys = current.map(normalizedToken)
        let nextKeys = next.map(normalizedToken)

        if nextKeys.count >= currentKeys.count,
           Array(nextKeys.prefix(currentKeys.count)) == currentKeys {
            return incoming
        }
        if currentKeys.count >= nextKeys.count,
           Array(currentKeys.suffix(nextKeys.count)) == nextKeys {
            return existing
        }

        let maximumOverlap = min(12, currentKeys.count, nextKeys.count)
        var overlap = 0
        if maximumOverlap > 0 {
            for count in stride(from: maximumOverlap, through: 1, by: -1) {
                if Array(currentKeys.suffix(count))
                    == Array(nextKeys.prefix(count)) {
                    overlap = count
                    break
                }
            }
        }

        return (current + next.dropFirst(overlap)).joined(separator: " ")
    }

    private static func normalizedToken(_ token: String) -> String {
        token
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}

final class StreamingSessionGate {
    private let lock = NSLock()
    private var activeRequestID: UUID?

    func begin(_ requestID: UUID) {
        lock.lock()
        activeRequestID = requestID
        lock.unlock()
    }

    func end(_ requestID: UUID) {
        lock.lock()
        if activeRequestID == requestID {
            activeRequestID = nil
        }
        lock.unlock()
    }

    func isActive(_ requestID: UUID) -> Bool {
        lock.lock()
        let active = activeRequestID == requestID
        lock.unlock()
        return active
    }
}
