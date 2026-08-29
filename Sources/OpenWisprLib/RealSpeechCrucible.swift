import AVFoundation
import Foundation

/// Staged text hops that match live `VocabularyLearner.postProcess` order.
///
/// Production order is not the operator's question list. The crucible records
/// both: this struct is production order; the report maps them to the mission
/// labels (vocabulary, cohesion, nearby, correction/spelling, final).
public struct RealSpeechTextStages: Equatable, Sendable {
    public let rawASR: String
    public let afterVocabulary: String
    public let vocabularyCorrections: [String]
    public let afterCohesion: String
    public let afterNearby: String
    public let afterPoker: String
    public let afterFigures: String
    public let nearbyNames: [String]

    public var finalText: String { afterFigures }
}

public struct RealSpeechManifest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let description: String
    public let samples: [RealSpeechSample]
}

public struct RealSpeechSample: Codable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let condition: String
    public let spokenScript: String
    public let reference: String
    public let criticalTokens: [String]
    public let audioFile: String
    public let nearbyNames: [String]
    public let pokerProfile: Bool

    enum CodingKeys: String, CodingKey {
        case id, category, condition, reference
        case spokenScript = "spoken_script"
        case criticalTokens = "critical_tokens"
        case audioFile = "audio_file"
        case nearbyNames = "nearby_names"
        case pokerProfile = "poker_profile"
    }

    public init(
        id: String,
        category: String,
        condition: String,
        spokenScript: String,
        reference: String,
        criticalTokens: [String],
        audioFile: String,
        nearbyNames: [String] = [],
        pokerProfile: Bool = false
    ) {
        self.id = id
        self.category = category
        self.condition = condition
        self.spokenScript = spokenScript
        self.reference = reference
        self.criticalTokens = criticalTokens
        self.audioFile = audioFile
        self.nearbyNames = nearbyNames
        self.pokerProfile = pokerProfile
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decode(String.self, forKey: .category)
        condition = try c.decode(String.self, forKey: .condition)
        spokenScript = try c.decode(String.self, forKey: .spokenScript)
        reference = try c.decode(String.self, forKey: .reference)
        criticalTokens = try c.decodeIfPresent([String].self, forKey: .criticalTokens) ?? []
        audioFile = try c.decode(String.self, forKey: .audioFile)
        nearbyNames = try c.decodeIfPresent([String].self, forKey: .nearbyNames) ?? []
        pokerProfile = try c.decodeIfPresent(Bool.self, forKey: .pokerProfile) ?? false
    }
}

public struct RealSpeechStageDump: Codable, Equatable, Sendable {
    public let name: String
    public let missionLabel: String
    public let text: String
    public let wordErrorsVsReference: Int
    public let werPercentVsReference: Double
    public let notes: [String]
}

public struct RealSpeechCaptureProbe: Codable, Equatable, Sendable {
    public let durationMilliseconds: Double
    public let sampleRate: Double
    public let peakAmplitude: Float
    public let activeDurationMilliseconds: Double
    public let containsLikelySpeech: Bool
    public let shouldAttemptTranscription: Bool
    public let rmsThresholdUsed: Float
}

public struct RealSpeechSampleTrace: Codable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let condition: String
    public let audioPath: String
    public let audioPresent: Bool
    public let capture: RealSpeechCaptureProbe?
    public let engineName: String?
    public let engineModel: String?
    public let engineRoute: String?
    public let asrMilliseconds: Double?
    public let stages: [RealSpeechStageDump]
    public let cleanupRoute: String
    public let acceptedByGate: Bool?
    public let finalText: String?
    public let firstLossStage: String?
    public let destructiveStages: [String]
    public let criticalTokenHits: Int
    public let criticalTokenTotal: Int
    public let limitations: [String]
}

public struct RealSpeechReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let generatedAt: String
    public let corpus: String
    public let audioSource: String
    public let enginePreference: String
    public let configuredModel: String
    public let samples: [RealSpeechSampleTrace]
    public let missingAudio: [String]
    public let aggregate: RealSpeechAggregate
    public let challengerQueue: [String]
    public let limitations: [String]
}

public struct RealSpeechAggregate: Codable, Equatable, Sendable {
    public let scoredSampleCount: Int
    public let missingAudioCount: Int
    public let wordErrorRatePercent: Double?
    public let criticalTokenRecallPercent: Double?
    public let medianAsrMilliseconds: Double?
    public let firstLossHistogram: [String: Int]
}

public enum RealSpeechCrucible {
    public static let schemaVersion = "local-voice-real-speech-crucible.v1"
    public static let challengerQueue = [
        "conservative adaptive normalization",
        "Silero learned VAD",
        "hybrid RMS + learned VAD",
        "RNNoise",
        "DeepFilterNet sandbox (license-gated)",
        "alternate-engine rescue routing",
        "operator-specific acoustic adaptation",
    ]

    public static func defaultManifestURL(
        repoRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL {
        repoRoot
            .appendingPathComponent("Benchmarks")
            .appendingPathComponent("real-speech-crucible")
            .appendingPathComponent("manifest.json")
    }

    public static func defaultAudioRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["LOCAL_VOICE_REAL_SPEECH_AUDIO"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Artifacts")
            .appendingPathComponent("local-voice")
            .appendingPathComponent("real-speech-crucible")
            .appendingPathComponent("audio")
    }

    public static func defaultTraceRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["LOCAL_VOICE_REAL_SPEECH_TRACES"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Artifacts")
            .appendingPathComponent("local-voice")
            .appendingPathComponent("real-speech-crucible")
            .appendingPathComponent("traces")
    }

    public static func loadManifest(from url: URL) throws -> RealSpeechManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RealSpeechManifest.self, from: data)
    }

    public static func status(
        manifest: RealSpeechManifest,
        audioRoot: URL = defaultAudioRoot()
    ) -> (present: [String], missing: [String]) {
        var present: [String] = []
        var missing: [String] = []
        for sample in manifest.samples {
            let url = audioRoot.appendingPathComponent(sample.audioFile)
            if FileManager.default.fileExists(atPath: url.path) {
                present.append(sample.id)
            } else {
                missing.append(sample.id)
            }
        }
        return (present, missing)
    }

    public static func probeCapture(url: URL) throws -> RealSpeechCaptureProbe {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            throw RealSpeechCrucibleError.unreadableAudio(url.path)
        }
        try file.read(into: buffer)
        var accumulator = SpeechActivityAccumulator(sampleRate: format.sampleRate)
        if let channel = buffer.floatChannelData?.pointee {
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            accumulator.observe(samples)
        }
        let metrics = accumulator.metrics
        return RealSpeechCaptureProbe(
            durationMilliseconds: metrics.sampleRate > 0
                ? 1000 * Double(metrics.totalFrames) / metrics.sampleRate
                : 0,
            sampleRate: metrics.sampleRate,
            peakAmplitude: metrics.peakAmplitude,
            activeDurationMilliseconds: metrics.activeDuration * 1000,
            containsLikelySpeech: metrics.containsLikelySpeech,
            shouldAttemptTranscription: metrics.shouldAttemptTranscription,
            rmsThresholdUsed: 0.004
        )
    }

    public static func stageDumps(
        reference: String,
        stages: RealSpeechTextStages,
        extraNotes: [String: [String]] = [:]
    ) -> [RealSpeechStageDump] {
        let rows: [(String, String, String)] = [
            ("raw_asr", "RAW ASR", stages.rawASR),
            ("vocabulary", "VOCABULARY", stages.afterVocabulary),
            ("cohesion", "COHESION / CLEANUP (deterministic)", stages.afterCohesion),
            ("nearby", "NEARBY CONTEXT", stages.afterNearby),
            ("poker", "CORRECTION / SPELLING (poker)", stages.afterPoker),
            ("figures", "CORRECTION / SPELLING (figures)", stages.afterFigures),
        ]
        return rows.map { name, label, text in
            let tokensRef = VoiceBenchmark.tokens(reference)
            let tokensHyp = VoiceBenchmark.tokens(text)
            let errors = VoiceBenchmark.editDistance(tokensRef, tokensHyp)
            let wer = tokensRef.isEmpty
                ? 0
                : 100 * Double(errors) / Double(tokensRef.count)
            var notes = extraNotes[name] ?? []
            if name == "vocabulary" {
                notes.append(contentsOf: stages.vocabularyCorrections)
            }
            if name == "nearby", stages.nearbyNames.isEmpty {
                notes.append("frozen corpus: no live focused-field spellings")
            }
            return RealSpeechStageDump(
                name: name,
                missionLabel: label,
                text: text,
                wordErrorsVsReference: errors,
                werPercentVsReference: (wer * 100).rounded() / 100,
                notes: notes
            )
        }
    }

    public static func firstLossStage(dumps: [RealSpeechStageDump]) -> String? {
        dumps.first(where: { $0.wordErrorsVsReference > 0 })?.name
    }

    public static func destructiveStages(dumps: [RealSpeechStageDump]) -> [String] {
        guard dumps.count >= 2 else { return [] }
        var lost: [String] = []
        for index in 1..<dumps.count {
            if dumps[index].wordErrorsVsReference > dumps[index - 1].wordErrorsVsReference {
                lost.append(dumps[index].name)
            }
        }
        return lost
    }

    public static func criticalTokenScore(tokens: [String], hypothesis: String) -> (Int, Int) {
        let haystack = VoiceBenchmark.tokens(hypothesis)
        let haystackJoined = haystack.joined(separator: " ")
        var hits = 0
        for token in tokens {
            let needle = VoiceBenchmark.tokens(token).joined(separator: " ")
            if !needle.isEmpty, haystackJoined.contains(needle) {
                hits += 1
            }
        }
        return (hits, tokens.count)
    }

    public static func run(
        manifest: RealSpeechManifest,
        audioRoot: URL = defaultAudioRoot(),
        preferredEngine: STTEngineKind,
        modelSize: String,
        language: String,
        configTerms: [String],
        ollamaEnabled: Bool,
        audioSource: String = "operator WAV fixtures; production STTRouter + postProcess"
    ) throws -> RealSpeechReport {
        let router = STTRouter(
            language: language,
            modelSize: modelSize,
            preferredEngine: preferredEngine
        )
        defer { router.shutdown() }
        router.warmup()

        var traces: [RealSpeechSampleTrace] = []
        var missing: [String] = []
        var totalErrors = 0
        var totalRefWords = 0
        var criticalHits = 0
        var criticalTotal = 0
        var latencies: [Double] = []
        var lossHistogram: [String: Int] = [:]

        for sample in manifest.samples {
            let audioURL = audioRoot.appendingPathComponent(sample.audioFile)
            let present = FileManager.default.fileExists(atPath: audioURL.path)
            if !present {
                missing.append(sample.id)
                traces.append(
                    RealSpeechSampleTrace(
                        id: sample.id,
                        category: sample.category,
                        condition: sample.condition,
                        audioPath: audioURL.path,
                        audioPresent: false,
                        capture: nil,
                        engineName: nil,
                        engineModel: nil,
                        engineRoute: nil,
                        asrMilliseconds: nil,
                        stages: [],
                        cleanupRoute: "skipped",
                        acceptedByGate: nil,
                        finalText: nil,
                        firstLossStage: "missing_audio",
                        destructiveStages: [],
                        criticalTokenHits: 0,
                        criticalTokenTotal: sample.criticalTokens.count,
                        limitations: ["No WAV on disk. Capture this item before scoring."]
                    )
                )
                continue
            }

            let capture = try probeCapture(url: audioURL)
            let started = DispatchTime.now().uptimeNanoseconds
            let raw = try router.transcribeInteractive(
                audioURL: audioURL,
                recordingMilliseconds: capture.durationMilliseconds
            )
            let asrMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            let stages = VocabularyLearner.shared.stagedPostProcess(
                raw,
                configTerms: configTerms,
                visibleSpellings: sample.nearbyNames,
                pokerVocabularyEnabled: sample.pokerProfile
            )
            let dumps = stageDumps(reference: sample.reference, stages: stages)
            let cleanup = DictationCleanupPolicy.route(
                enabled: ollamaEnabled,
                characterCount: stages.finalText.count,
                recordingMilliseconds: capture.durationMilliseconds
            )
            var finalText = stages.finalText
            var extraLimitations: [String] = []
            if cleanup == .synchronousOllama {
                extraLimitations.append(
                    "Ollama is enabled in config; crucible does not call it. Live dictation might still polish this take."
                )
            }
            let accepted = TranscriptAcceptanceGate.shouldAccept(
                raw: raw,
                polished: finalText,
                recordingMilliseconds: capture.durationMilliseconds,
                captureMetrics: AudioCaptureMetrics(
                    totalFrames: Int(
                        capture.durationMilliseconds / 1000 * capture.sampleRate
                    ),
                    activeFrames: Int(
                        capture.activeDurationMilliseconds / 1000 * capture.sampleRate
                    ),
                    peakAmplitude: capture.peakAmplitude,
                    sampleRate: capture.sampleRate
                )
            )
            if !accepted {
                extraLimitations.append(
                    "TranscriptAcceptanceGate would drop this take in live dictation."
                )
                finalText = ""
            }

            let firstLoss = firstLossStage(dumps: dumps)
            let destructive = destructiveStages(dumps: dumps)
            if let firstLoss {
                lossHistogram[firstLoss, default: 0] += 1
            }
            let (hits, total) = criticalTokenScore(
                tokens: sample.criticalTokens,
                hypothesis: accepted ? stages.finalText : ""
            )
            criticalHits += hits
            criticalTotal += total
            let refTokens = VoiceBenchmark.tokens(sample.reference)
            let hypTokens = VoiceBenchmark.tokens(accepted ? stages.finalText : "")
            totalErrors += VoiceBenchmark.editDistance(refTokens, hypTokens)
            totalRefWords += refTokens.count
            latencies.append(asrMs)

            traces.append(
                RealSpeechSampleTrace(
                    id: sample.id,
                    category: sample.category,
                    condition: sample.condition,
                    audioPath: audioURL.path,
                    audioPresent: true,
                    capture: capture,
                    engineName: router.activeEngineName(),
                    engineModel: router.activeEngineModelName(),
                    engineRoute: router.activeExecutionRoute().rawValue,
                    asrMilliseconds: (asrMs * 10).rounded() / 10,
                    stages: dumps,
                    cleanupRoute: cleanup.rawValue,
                    acceptedByGate: accepted,
                    finalText: accepted ? stages.finalText : "",
                    firstLossStage: firstLoss,
                    destructiveStages: destructive,
                    criticalTokenHits: hits,
                    criticalTokenTotal: total,
                    limitations: extraLimitations
                )
            )
        }

        let scored = traces.filter(\.audioPresent).count
        let wer: Double? = totalRefWords == 0
            ? nil
            : (10000 * Double(totalErrors) / Double(totalRefWords)).rounded() / 100
        let recall: Double? = criticalTotal == 0
            ? nil
            : (10000 * Double(criticalHits) / Double(criticalTotal)).rounded() / 100

        return RealSpeechReport(
            schemaVersion: schemaVersion,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            corpus: "RS-001...RS-012",
            audioSource: audioSource,
            enginePreference: preferredEngine.rawValue,
            configuredModel: modelSize,
            samples: traces,
            missingAudio: missing,
            aggregate: RealSpeechAggregate(
                scoredSampleCount: scored,
                missingAudioCount: missing.count,
                wordErrorRatePercent: scored == 0 ? nil : wer,
                criticalTokenRecallPercent: scored == 0 ? nil : recall,
                medianAsrMilliseconds: latencies.isEmpty
                    ? nil
                    : VoiceBenchmark.percentile(latencies, fraction: 0.50),
                firstLossHistogram: lossHistogram
            ),
            challengerQueue: challengerQueue,
            limitations: [
                "Synthetic TTS is not this corpus. Operator WAVs are the source of truth.",
                "Nearby context is frozen from the manifest. Live focused-field sampling is not applied.",
                "Ollama polish is reported as a route, not executed, so the baseline matches local STT+deterministic cleanup.",
                "Do not adopt Silero, RNNoise, DeepFilterNet, or another ASR until this baseline exists.",
            ]
        )
    }

    public static func encode(_ report: RealSpeechReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}

public enum RealSpeechCrucibleError: LocalizedError {
    case unreadableAudio(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableAudio(let path):
            return "Could not read real-speech fixture at \(path)"
        }
    }
}
