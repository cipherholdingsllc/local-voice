import Foundation

public enum STTExecutionRoute: String, Sendable {
    case localProcess = "local_process"
    case localLoopback = "local_loopback"

    public var label: String {
        switch self {
        case .localProcess: return "local process"
        case .localLoopback: return "local loopback"
        }
    }
}

/// STT engine abstraction for dual-engine routing (#4).
public protocol STTEngine: AnyObject {
    var name: String { get }
    var modelName: String? { get }
    var executionRoute: STTExecutionRoute { get }
    var isPersistent: Bool { get }
    func isAvailable() -> Bool
    func warmup() throws
    func transcribe(audioURL: URL) throws -> String
    func shutdown()
}

public extension STTEngine {
    var modelName: String? { nil }
    var isPersistent: Bool { false }
    func shutdown() {}
}

public enum STTEngineKind: String, Codable, Sendable {
    case auto
    case parakeet
    case whisper
}

public final class STTRouter {
    public let language: String
    public let preferredEngine: STTEngineKind
    private let parakeet: STTEngine
    private let whisper: STTEngine
    private let whisperFallback: STTEngine
    private let healthLock = NSLock()
    private var parakeetHealthy = true
    private var whisperHealthy = true

    public init(
        language: String,
        modelSize: String,
        preferredEngine: STTEngineKind = .auto,
        spokenPunctuation: Bool = false,
        initialPrompt: String? = nil
    ) {
        let fallback = Transcriber(modelSize: modelSize, language: language)
        fallback.spokenPunctuation = spokenPunctuation
        fallback.initialPrompt = initialPrompt
        self.language = language
        self.preferredEngine = preferredEngine
        self.parakeet = ParakeetDaemon.shared
        self.whisper = WhisperServerPool(
            modelSize: modelSize,
            language: language
        )
        self.whisperFallback = fallback
    }

    init(
        language: String,
        preferredEngine: STTEngineKind,
        parakeet: STTEngine,
        whisper: STTEngine,
        whisperFallback: STTEngine
    ) {
        self.language = language
        self.preferredEngine = preferredEngine
        self.parakeet = parakeet
        self.whisper = whisper
        self.whisperFallback = whisperFallback
    }

    public func warmup() {
        if shouldUseParakeet(), parakeetCanRun() {
            do {
                try parakeet.warmup()
                setParakeetHealthy(true)
                return
            } catch {
                setParakeetHealthy(false)
                fputs(
                    "STTRouter: Parakeet warmup failed (\(error.localizedDescription)); warming Whisper\n",
                    stderr
                )
            }
        }
        if whisperCanRun() {
            do {
                try whisper.warmup()
                setWhisperHealthy(true)
                return
            } catch {
                setWhisperHealthy(false)
                fputs(
                    "STTRouter: whisper-server warmup failed (\(error.localizedDescription)); warming CLI fallback\n",
                    stderr
                )
            }
        }
        if whisperFallback.isAvailable() {
            try? whisperFallback.warmup()
        }
    }

    public func transcribe(audioURL: URL) throws -> String {
        if shouldUseParakeet(), parakeetCanRun() {
            do {
                let text = try parakeet.transcribe(audioURL: audioURL)
                setParakeetHealthy(true)
                return text
            } catch {
                setParakeetHealthy(false)
                fputs("STTRouter: Parakeet failed (\(error.localizedDescription)), falling back to Whisper\n", stderr)
            }
        }
        if whisperCanRun() {
            do {
                let text = try whisper.transcribe(audioURL: audioURL)
                setWhisperHealthy(true)
                return text
            } catch {
                setWhisperHealthy(false)
                fputs("STTRouter: whisper-server failed (\(error.localizedDescription)), falling back to CLI\n", stderr)
            }
        }
        return try whisperFallback.transcribe(audioURL: audioURL)
    }

    public func chunkEngine() -> STTEngine? {
        if shouldUseParakeet(), parakeetCanRun() { return parakeet }
        if whisperCanRun() { return whisper }
        return nil
    }

    public func activeEngineName() -> String {
        activeEngine().name
    }

    public func activeExecutionRoute() -> STTExecutionRoute {
        activeEngine().executionRoute
    }

    public func activeEngineModelName() -> String? {
        activeEngine().modelName
    }

    public func activeEngineIsPersistent() -> Bool {
        activeEngine().isPersistent
    }

    public func hasAvailableLocalEngine() -> Bool {
        activeEngine().isAvailable()
    }

    public func shutdown() {
        parakeet.shutdown()
        whisper.shutdown()
        whisperFallback.shutdown()
    }

    private func activeEngine() -> STTEngine {
        if shouldUseParakeet(), parakeetCanRun() { return parakeet }
        if whisperCanRun() { return whisper }
        return whisperFallback
    }

    private func parakeetCanRun() -> Bool {
        healthLock.lock()
        let healthy = parakeetHealthy
        healthLock.unlock()
        return healthy && parakeet.isAvailable()
    }

    private func whisperCanRun() -> Bool {
        healthLock.lock()
        let healthy = whisperHealthy
        healthLock.unlock()
        return healthy && whisper.isAvailable()
    }

    private func setParakeetHealthy(_ healthy: Bool) {
        healthLock.lock()
        parakeetHealthy = healthy
        healthLock.unlock()
    }

    private func setWhisperHealthy(_ healthy: Bool) {
        healthLock.lock()
        whisperHealthy = healthy
        healthLock.unlock()
    }

    private func shouldUseParakeet() -> Bool {
        switch preferredEngine {
        case .parakeet: return true
        case .whisper: return false
        case .auto: return language == "en" || language == "auto"
        }
    }
}
