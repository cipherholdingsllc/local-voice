import Foundation

/// Wall-clock budget for a single STT call.
///
/// `whisper-server` posts the whole WAV then waits for JSON. A fixed 120s
/// `URLRequest.timeoutInterval` (and matching semaphore wait) is enough for
/// ~90s takes and silently drops multi-minute locked sessions: the request
/// dies, and if a persistent engine hangs without throwing, CLI never runs.
public enum InferenceTimeout {
    public static let minimumSeconds: TimeInterval = 120
    public static let maximumSeconds: TimeInterval = 3_600
    public static let chunkMaximumSeconds: TimeInterval = 45
    public static let realtimeFactor: Double = 2.5
    public static let overheadSeconds: TimeInterval = 90
    public static let waitLeewaySeconds: TimeInterval = 8
    /// Takes at least this long treat an empty persistent-engine transcript
    /// as failure so CLI can recover from the full WAV.
    public static let longFormEmptyIsFailureMilliseconds: Double = 90_000

    public static func httpSeconds(
        durationSeconds: TimeInterval,
        isChunk: Bool = false
    ) -> TimeInterval {
        if isChunk || durationSeconds <= 8 {
            let chunk = max(15, durationSeconds * 8 + 10)
            return min(chunkMaximumSeconds, chunk)
        }
        let scaled = durationSeconds * realtimeFactor + overheadSeconds
        return min(maximumSeconds, max(minimumSeconds, scaled))
    }

    public static func httpSeconds(forAudioURL url: URL) -> TimeInterval {
        httpSeconds(
            durationSeconds: wavDurationSeconds(url: url) ?? 0,
            isChunk: false
        )
    }

    public static func processWaitSeconds(httpSeconds: TimeInterval) -> TimeInterval {
        min(maximumSeconds + waitLeewaySeconds, httpSeconds + waitLeewaySeconds)
    }

    public static func cliSeconds(durationSeconds: TimeInterval) -> TimeInterval {
        let scaled = durationSeconds * 3 + 120
        return min(maximumSeconds, max(minimumSeconds, scaled))
    }

    public static func cliSeconds(forAudioURL url: URL) -> TimeInterval {
        cliSeconds(durationSeconds: wavDurationSeconds(url: url) ?? 0)
    }

    public static func shouldRecoverFromEmptyTranscript(
        recordingMilliseconds: Double?
    ) -> Bool {
        guard let recordingMilliseconds else { return false }
        return recordingMilliseconds >= longFormEmptyIsFailureMilliseconds
    }

    public static func isTimeout(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return true
        }
        if case WhisperServerError.timeout = error { return true }
        if case TranscriberError.timeout = error { return true }
        if case ParakeetError.timeout = error { return true }
        return false
    }

    public static func wavDurationSeconds(url: URL) -> TimeInterval? {
        if let contract = try? LocalVoiceContract.audioDescriptor(for: url) {
            return Double(contract.durationMs) / 1_000
        }
        return wavDurationFromHeader(url: url)
    }

    /// PCM WAV duration from a RIFF header when AVAudioFile cannot open the file.
    public static func wavDurationFromHeader(url: URL) -> TimeInterval? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 44)
        guard header.count >= 44 else { return nil }
        let riff = header.subdata(in: 0..<4)
        let wave = header.subdata(in: 8..<12)
        guard String(data: riff, encoding: .ascii) == "RIFF",
              String(data: wave, encoding: .ascii) == "WAVE" else {
            return nil
        }
        let sampleRate = header.uint32LE(at: 24)
        let byteRate = header.uint32LE(at: 28)
        let dataSize = header.uint32LE(at: 40)
        if byteRate > 0 {
            return Double(dataSize) / Double(byteRate)
        }
        if sampleRate > 0 {
            return Double(dataSize) / Double(sampleRate * 2)
        }
        return nil
    }
}

private extension Data {
    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
