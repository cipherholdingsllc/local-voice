import Foundation

/// STT engine abstraction for dual-engine routing (#4).
public protocol STTEngine: AnyObject {
    var name: String { get }
    func isAvailable() -> Bool
    func warmup() throws
    func transcribe(audioURL: URL) throws -> String
}

public enum STTEngineKind: String, Codable, Sendable {
    case auto
    case parakeet
    case whisper
}

public final class STTRouter {
    public let language: String
    public let preferredEngine: STTEngineKind
    private let parakeet: ParakeetDaemon
    private let whisper: WhisperServerPool
    private let whisperFallback: Transcriber

    public init(
        language: String,
        modelSize: String,
        preferredEngine: STTEngineKind = .auto,
        spokenPunctuation: Bool = false,
        initialPrompt: String? = nil
    ) {
        self.language = language
        self.preferredEngine = preferredEngine
        self.parakeet = ParakeetDaemon.shared
        self.whisper = WhisperServerPool(modelSize: modelSize, language: language)
        self.whisperFallback = Transcriber(modelSize: modelSize, language: language)
        self.whisperFallback.spokenPunctuation = spokenPunctuation
        self.whisperFallback.initialPrompt = initialPrompt
    }

    public func warmup() {
        if shouldUseParakeet() {
            try? parakeet.ensureRunning()
            try? parakeet.warmup()
        }
        if shouldUseWhisper() {
            try? whisper.ensureRunning()
            WhisperWarmKeeper.warmup(transcriber: whisperFallback)
        }
    }

    public func transcribe(audioURL: URL) throws -> String {
        if shouldUseParakeet(), parakeet.isAvailable() {
            do {
                return try parakeet.transcribe(audioURL: audioURL)
            } catch {
                fputs("STTRouter: Parakeet failed (\(error.localizedDescription)), falling back to Whisper\n", stderr)
            }
        }
        if whisper.isAvailable() {
            do {
                return try whisper.transcribe(audioURL: audioURL)
            } catch {
                fputs("STTRouter: whisper-server failed (\(error.localizedDescription)), falling back to CLI\n", stderr)
            }
        }
        return try whisperFallback.transcribe(audioURL: audioURL)
    }

    public func chunkEngine() -> STTEngine? {
        if shouldUseParakeet(), parakeet.isAvailable() { return parakeet }
        if whisper.isAvailable() { return whisper }
        return nil
    }

    public func activeEngineName() -> String {
        if shouldUseParakeet(), parakeet.isAvailable() { return "Parakeet TDT-0.6b" }
        if whisper.isAvailable() { return "whisper-server (\(whisper.modelSize))" }
        return "whisper-cli (\(whisperFallback.modelSize))"
    }

    private func shouldUseParakeet() -> Bool {
        switch preferredEngine {
        case .parakeet: return true
        case .whisper: return false
        case .auto: return language == "en" || language == "auto"
        }
    }

    private func shouldUseWhisper() -> Bool {
        switch preferredEngine {
        case .whisper: return true
        case .parakeet: return false
        case .auto: return language != "en"
        }
    }
}