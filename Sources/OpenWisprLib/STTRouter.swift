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
    public static let interactiveWhisperMaxMilliseconds = 8_000.0

    public let language: String
    public let preferredEngine: STTEngineKind
    private let interactiveAccuracyFirst: Bool
    private let parakeet: STTEngine
    private let whisper: STTEngine
    private let whisperFallback: STTEngine
    private var initialPrompt: String?
    private let healthLock = NSLock()
    private var parakeetHealthy = true
    private var whisperHealthy = true
    private var lastUsedEngine: STTEngine?

    public init(
        language: String,
        modelSize: String,
        preferredEngine: STTEngineKind = .auto,
        spokenPunctuation: Bool = false,
        initialPrompt: String? = nil,
        interactiveAccuracyFirst: Bool = true
    ) {
        let fallback = Transcriber(modelSize: modelSize, language: language)
        fallback.spokenPunctuation = spokenPunctuation
        fallback.initialPrompt = initialPrompt
        self.initialPrompt = initialPrompt
        self.interactiveAccuracyFirst = interactiveAccuracyFirst
        self.language = language
        self.preferredEngine = preferredEngine
        self.parakeet = ParakeetDaemon.shared
        self.whisper = WhisperServerPool(
            modelSize: modelSize,
            language: language,
            initialPrompt: initialPrompt
        )
        self.whisperFallback = fallback
    }

    init(
        language: String,
        preferredEngine: STTEngineKind,
        interactiveAccuracyFirst: Bool = true,
        parakeet: STTEngine,
        whisper: STTEngine,
        whisperFallback: STTEngine
    ) {
        self.language = language
        self.preferredEngine = preferredEngine
        self.interactiveAccuracyFirst = interactiveAccuracyFirst
        self.parakeet = parakeet
        self.whisper = whisper
        self.whisperFallback = whisperFallback
    }

    public func warmup() {
        var parakeetWarmed = false
        if shouldUseParakeet(), parakeetCanRun() {
            do {
                try parakeet.warmup()
                setParakeetHealthy(true)
                parakeetWarmed = true
            } catch {
                setParakeetHealthy(false)
                fputs(
                    "STTRouter: Parakeet warmup failed (\(error.localizedDescription)); warming Whisper\n",
                    stderr
                )
            }
        }

        // Accuracy-first uses Parakeet for final takes and live preview.
        // The fast path still warms Whisper for short utterances. Warm both
        // off the main thread so neither route pays a first-use penalty.
        if parakeetWarmed, usesHybridInteractiveRoute() {
            if whisperCanRun() {
                do {
                    try whisper.warmup()
                    setWhisperHealthy(true)
                } catch {
                    setWhisperHealthy(false)
                    fputs(
                        "STTRouter: short-route whisper warmup failed (\(error.localizedDescription)); Parakeet remains available\n",
                        stderr
                    )
                }
            }
            return
        }
        if parakeetWarmed { return }

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
                setLastUsedEngine(parakeet)
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
                setLastUsedEngine(whisper)
                return text
            } catch {
                setWhisperHealthy(false)
                fputs("STTRouter: whisper-server failed (\(error.localizedDescription)), falling back to CLI\n", stderr)
            }
        }
        let text = try whisperFallback.transcribe(audioURL: audioURL)
        setLastUsedEngine(whisperFallback)
        return text
    }

    public func transcribeInteractive(
        audioURL: URL,
        recordingMilliseconds: Double
    ) throws -> String {
        guard usesHybridInteractiveRoute(),
              !interactiveAccuracyFirst,
              recordingMilliseconds
                <= Self.interactiveWhisperMaxMilliseconds,
              whisperCanRun() else {
            return try transcribe(audioURL: audioURL)
        }

        do {
            let text = try whisper.transcribe(audioURL: audioURL)
            setWhisperHealthy(true)
            setLastUsedEngine(whisper)
            return text
        } catch {
            setWhisperHealthy(false)
            fputs(
                "STTRouter: short-route whisper failed (\(error.localizedDescription)); using Parakeet\n",
                stderr
            )
            return try transcribe(audioURL: audioURL)
        }
    }

    public func chunkEngine() -> STTEngine? {
        if usesHybridInteractiveRoute() {
            if interactiveAccuracyFirst, parakeetCanRun() { return parakeet }
            if whisperCanRun() { return whisper }
        }
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

    public func updateInitialPrompt(_ prompt: String?) {
        initialPrompt = prompt
        if let pool = whisper as? WhisperServerPool {
            pool.updateInitialPrompt(prompt)
        }
        (whisperFallback as? Transcriber)?.initialPrompt = prompt
    }

    public func shutdown(preserveParakeet: Bool = false) {
        if !preserveParakeet {
            parakeet.shutdown()
        }
        whisper.shutdown()
        whisperFallback.shutdown()
    }

    private func activeEngine() -> STTEngine {
        healthLock.lock()
        let lastUsedEngine = self.lastUsedEngine
        healthLock.unlock()
        if let lastUsedEngine, lastUsedEngine.isAvailable() {
            return lastUsedEngine
        }
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

    private func setLastUsedEngine(_ engine: STTEngine) {
        healthLock.lock()
        lastUsedEngine = engine
        healthLock.unlock()
    }

    private func usesHybridInteractiveRoute() -> Bool {
        preferredEngine == .auto
            && (language == "en" || language == "auto")
    }

    private func shouldUseParakeet() -> Bool {
        switch preferredEngine {
        case .parakeet: return true
        case .whisper: return false
        case .auto: return language == "en" || language == "auto"
        }
    }
}
