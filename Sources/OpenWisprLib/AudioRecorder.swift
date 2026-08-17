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
    private var sessionCapGeneration: UInt64 = 0
    private var silenceTimer: Timer?
    private var lastLoudTime: Date = Date()
    private var silenceThreshold: Float = 0.02
    private var silenceTimeout: TimeInterval = 3.0
    var onSessionCap: (() -> Void)?
    var onSilenceTimeout: (() -> Void)?
    private let speechActivityLock = NSLock()
    private var speechActivity = SpeechActivityAccumulator()

    /// Apple's Voice Processing I/O can zero-out some external/USB mics.
    /// Default off; enable only when verified on the operator's hardware.
    var voiceProcessingRequested = false
    private(set) var voiceProcessingActive = false

    func prewarm() {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()

        if let deviceID = preferredDeviceID,
           deviceID != AudioDeviceManager.getDefaultInputDeviceID() {
            setInputDevice(deviceID, on: engine)
        }

        let inputNode = engine.inputNode
        voiceProcessingActive = false
        if voiceProcessingRequested {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                voiceProcessingActive = inputNode.isVoiceProcessingEnabled
            } catch {
                fputs(
                    "AudioRecorder: voice processing unavailable; using raw input (\(error.localizedDescription))\n",
                    stderr
                )
            }
        }
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
        voiceProcessingActive = false
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
        speechActivityLock.withLock {
            speechActivity.reset()
        }
        if let s = silenceTimeoutSeconds { silenceTimeout = s }

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
                if let channel = convertedBuffer.floatChannelData?[0] {
                    let samples = Array(
                        UnsafeBufferPointer(
                            start: channel,
                            count: Int(convertedBuffer.frameLength)
                        )
                    )
                    self.speechActivityLock.withLock {
                        self.speechActivity.observe(samples)
                    }
                    if streamPreviewEnabled, let streamCallback {
                        self.enqueueStreamingSamples(
                            samples,
                            outputURL: outputURL,
                            onChunkReady: streamCallback
                        )
                    }
                }
            }
        }

        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }

        currentOutputURL = outputURL
        isRecording = true
        updateSessionCap(seconds: sessionCapSeconds)

        if silenceTimeoutSeconds != nil {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleSilenceTimer()
            }
        }
    }

    /// Replaces the active session limit. Passing nil removes the limit.
    /// A generation token prevents an asynchronously scheduled timer from a
    /// cancelled speculative fn tap from arming a later locked recording.
    func updateSessionCap(seconds: TimeInterval?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateSessionCap(seconds: seconds)
            }
            return
        }

        sessionCapGeneration &+= 1
        let generation = sessionCapGeneration
        sessionCapTimer?.invalidate()
        sessionCapTimer = nil

        guard isRecording, let seconds, seconds > 0 else { return }
        sessionCapTimer = Timer.scheduledTimer(
            withTimeInterval: seconds,
            repeats: false
        ) { [weak self] _ in
            guard let self,
                  self.isRecording,
                  self.sessionCapGeneration == generation else { return }
            self.onSessionCap?()
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

        sessionCapGeneration &+= 1
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

    func captureMetricsSnapshot() -> AudioCaptureMetrics {
        speechActivityLock.withLock {
            speechActivity.metrics
        }
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

struct AudioCaptureMetrics: Equatable {
    let totalFrames: Int
    let activeFrames: Int
    let peakAmplitude: Float
    let sampleRate: Double

    var activeDuration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(activeFrames) / sampleRate
    }

    /// Reject only clearly empty captures. Quiet microphones often sit below
    /// the old peak gate even while the user is speaking, which caused
    /// listening UI with zero transcription.
    var containsLikelySpeech: Bool {
        guard totalFrames > 0 else { return false }
        if peakAmplitude < 0.0005, activeDuration < 0.05 { return false }
        return peakAmplitude >= 0.006 || activeDuration >= 0.02
    }

    /// When the user held the hotkey long enough, always attempt STT even if
    /// level detection is uncertain. Whisper handles silence better than we
    /// handle silently dropping real speech.
    var shouldAttemptTranscription: Bool {
        guard totalFrames > 0 else { return false }
        let duration = Double(totalFrames) / max(sampleRate, 1)
        if duration < 0.15 { return false }
        if duration >= 0.25 { return true }
        return containsLikelySpeech
    }
}

struct SpeechActivityAccumulator {
    private(set) var totalFrames = 0
    private(set) var activeFrames = 0
    private(set) var peakAmplitude: Float = 0
    let sampleRate: Double
    let rmsThreshold: Float
    let peakThreshold: Float

    init(
        sampleRate: Double = 16_000,
        rmsThreshold: Float = 0.004,
        peakThreshold: Float = 0.006
    ) {
        self.sampleRate = sampleRate
        self.rmsThreshold = rmsThreshold
        self.peakThreshold = peakThreshold
    }

    mutating func observe(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        var bufferPeak: Float = 0
        var bufferActiveFrames = 0
        for sample in samples {
            let magnitude = abs(sample)
            bufferPeak = max(bufferPeak, magnitude)
            if magnitude >= peakThreshold {
                bufferActiveFrames += 1
            }
        }
        totalFrames += samples.count
        peakAmplitude = max(peakAmplitude, bufferPeak)
        if bufferPeak >= peakThreshold {
            activeFrames += bufferActiveFrames
        }
    }

    mutating func reset() {
        totalFrames = 0
        activeFrames = 0
        peakAmplitude = 0
    }

    var metrics: AudioCaptureMetrics {
        AudioCaptureMetrics(
            totalFrames: totalFrames,
            activeFrames: activeFrames,
            peakAmplitude: peakAmplitude,
            sampleRate: sampleRate
        )
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
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
