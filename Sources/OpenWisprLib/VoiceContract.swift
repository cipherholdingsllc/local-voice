import AVFoundation
import Foundation

public enum VoiceContractProfileID: String, Codable, CaseIterable, Sendable {
    case generalDefault = "general.default"
    case generalMessage = "general.message"
    case generalProfessional = "general.professional"
    case generalTechnical = "general.technical"
    case generalCommand = "general.command"
    case generalLongForm = "general.long_form"
    case pokerExploit = "poker.exploit"

    public var maximumDurationMilliseconds: Int {
        switch self {
        case .generalCommand, .pokerExploit:
            return 120_000
        case .generalDefault, .generalMessage, .generalProfessional,
             .generalTechnical:
            return 600_000
        case .generalLongForm:
            return 3_600_000
        }
    }

    public var isGeneral: Bool {
        self != .pokerExploit
    }

    public static func localVoiceProfile(
        bundleIdentifier: String?,
        modeName: String?
    ) -> VoiceContractProfileID {
        if let bundle = bundleIdentifier?.lowercased() {
            if bundle.contains("exploitpoker")
                || bundle.contains("exploit-poker")
                || bundle.contains("pokergod") {
                return .pokerExploit
            }
        }

        switch modeName?.lowercased() {
        case "exploit poker", "poker", "pokergod":
            return .pokerExploit
        default:
            break
        }

        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            return .generalMessage
        case "com.google.Gmail", "com.apple.mail":
            return .generalProfessional
        case "com.microsoft.VSCode", "com.openai.codex":
            return .generalTechnical
        case "com.apple.Terminal", "com.googlecode.iterm2":
            return .generalCommand
        default:
            break
        }

        switch modeName?.lowercased() {
        case "quick message", "message", "slack":
            return .generalMessage
        case "professional", "gmail", "mail":
            return .generalProfessional
        case "technical", "vs code", "codex":
            return .generalTechnical
        case "command", "terminal", "iterm":
            return .generalCommand
        default:
            return .generalDefault
        }
    }
}

public enum VoiceContractOrigin: String, Codable, Sendable {
    case localVoiceMacOS = "local_voice_macos"
    case localVoiceIOS = "local_voice_ios"
    case exploitPoker = "exploit_poker"
}

public enum VoiceContractRoute: String, Codable, Sendable {
    case localProcess = "local_process"
    case localLoopback = "local_loopback"
    case appleOnDevice = "apple_on_device"

    init(_ route: STTExecutionRoute) {
        switch route {
        case .localProcess: self = .localProcess
        case .localLoopback: self = .localLoopback
        }
    }
}

public enum VoiceContractEnginePreference: String, Codable, Sendable {
    case auto
    case whisper
    case parakeet
    case appleOnDevice = "apple_on_device"

    init(_ preference: STTEngineKind) {
        switch preference {
        case .auto: self = .auto
        case .whisper: self = .whisper
        case .parakeet: self = .parakeet
        }
    }
}

public enum VoiceContractTranscriptRetention: String, Codable, Sendable {
    case none
    case localSession = "local_session"
    case localHistory = "local_history"
}

public enum VoiceContractNetworkEgress: String, Codable, Sendable {
    case none
    case loopbackOnly = "loopback_only"
}

public enum VoiceContractNullableString: Codable, Equatable, Sendable {
    case value(String)
    case null

    public init(_ value: String?) {
        if let value {
            self = .value(value)
        } else {
            self = .null
        }
    }

    public var value: String? {
        switch self {
        case .value(let value): return value
        case .null: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .value(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct VoiceContractAudio: Codable, Equatable, Sendable {
    public let contentType: String
    public let encoding: String
    public let sampleRateHz: Int
    public let channels: Int
    public let byteLength: Int
    public let durationMs: Int

    public init(byteLength: Int, durationMs: Int) {
        self.contentType = "audio/wav"
        self.encoding = "pcm_s16le"
        self.sampleRateHz = 16_000
        self.channels = 1
        self.byteLength = byteLength
        self.durationMs = durationMs
    }
}

public struct VoiceContractLanguagePolicy: Codable, Equatable, Sendable {
    public let requested: String
    public let allowDetection: Bool
}

public struct VoiceContractEnginePolicy: Codable, Equatable, Sendable {
    public let preference: VoiceContractEnginePreference
    public let model: VoiceContractNullableString
    public let keepWarm: Bool
}

public struct VoiceContractRetention: Codable, Equatable, Sendable {
    public let audio: String
    public let transcript: VoiceContractTranscriptRetention

    public init(transcript: VoiceContractTranscriptRetention) {
        self.audio = "none"
        self.transcript = transcript
    }
}

public struct VoiceContractRequestV1: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestId: String
    public let profileId: VoiceContractProfileID
    public let origin: VoiceContractOrigin
    public let audio: VoiceContractAudio
    public let languagePolicy: VoiceContractLanguagePolicy
    public let enginePolicy: VoiceContractEnginePolicy
    public let promptVocabulary: [String]
    public let maximumDurationMs: Int
    public let retention: VoiceContractRetention
}

public struct VoiceContractTranscript: Codable, Equatable, Sendable {
    public let raw: VoiceContractNullableString
    public let normalized: String
}

public struct VoiceContractEngine: Codable, Equatable, Sendable {
    public let name: String
    public let model: VoiceContractNullableString
    public let route: VoiceContractRoute
    public let persistent: Bool
}

public struct VoiceContractLanguage: Codable, Equatable, Sendable {
    public let requested: String
    public let detected: VoiceContractNullableString
}

public struct VoiceContractTiming: Codable, Equatable, Sendable {
    public let audioMs: Double
    public let inferenceMs: Double
    public let finishMs: Double
    public let totalMs: Double
}

public struct VoiceContractWarning: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
}

public struct VoiceContractPrivacy: Codable, Equatable, Sendable {
    public let route: VoiceContractRoute
    public let audioRetained: Bool
    public let transcriptRetention: VoiceContractTranscriptRetention
    public let networkEgress: VoiceContractNetworkEgress
}

public struct VoiceContractDiagnostics: Codable, Equatable, Sendable {
    public let realtimeFactor: Double
}

public struct VoiceContractResponseV1: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestId: String
    public let profileId: VoiceContractProfileID
    public let origin: VoiceContractOrigin
    public let transcript: VoiceContractTranscript
    public let engine: VoiceContractEngine
    public let language: VoiceContractLanguage
    public let timing: VoiceContractTiming
    public let warnings: [VoiceContractWarning]
    public let privacy: VoiceContractPrivacy
    public let diagnostics: VoiceContractDiagnostics
}

public struct VoiceContractPair: Codable, Equatable, Sendable {
    public let request: VoiceContractRequestV1
    public let response: VoiceContractResponseV1

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public enum LocalVoiceContract {
    public static func audioDescriptor(
        for url: URL
    ) throws -> VoiceContractAudio {
        guard url.pathExtension.lowercased() == "wav" else {
            throw VoiceContractError.unsupportedAudio
        }
        let file = try AVAudioFile(forReading: url)
        let format = file.fileFormat
        guard abs(format.sampleRate - 16_000) < 1,
              format.channelCount == 1,
              format.commonFormat == .pcmFormatInt16 else {
            throw VoiceContractError.unsupportedAudio
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        guard let bytes = attributes[.size] as? NSNumber else {
            throw VoiceContractError.unsupportedAudio
        }
        let duration = Int(
            (Double(file.length) / format.sampleRate * 1_000).rounded()
        )
        return VoiceContractAudio(
            byteLength: bytes.intValue,
            durationMs: max(1, duration)
        )
    }

    public static func makePair(
        requestId: UUID,
        profileId: VoiceContractProfileID,
        audio: VoiceContractAudio,
        requestedLanguage: String,
        detectedLanguage: String?,
        enginePreference: STTEngineKind,
        configuredModel: String?,
        keepWarm: Bool,
        promptVocabulary: [String],
        maximumDurationMilliseconds: Int,
        rawTranscript: String?,
        normalizedTranscript: String,
        engineName: String,
        engineModel: String?,
        engineRoute: STTExecutionRoute,
        enginePersistent: Bool,
        inferenceMilliseconds: Double,
        finishMilliseconds: Double,
        transcriptRetention: VoiceContractTranscriptRetention
    ) throws -> VoiceContractPair {
        guard profileId.isGeneral else {
            throw VoiceContractError.productProfileMismatch
        }
        let maximumAudioBytes = profileId == .generalLongForm
            ? 134_217_728
            : 33_554_432
        guard audio.byteLength >= 44,
              audio.byteLength <= maximumAudioBytes,
              audio.durationMs >= 1,
              audio.durationMs <= profileId.maximumDurationMilliseconds,
              maximumDurationMilliseconds >= 1_000,
              maximumDurationMilliseconds <= profileId.maximumDurationMilliseconds,
              audio.durationMs <= maximumDurationMilliseconds else {
            throw VoiceContractError.invalidAudioBounds
        }
        guard isBounded(requestedLanguage, maximum: 35),
              detectedLanguage.map({
                  isBounded($0, maximum: 35)
              }) ?? true else {
            throw VoiceContractError.invalidLanguage
        }
        let normalized = normalizedTranscript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            throw VoiceContractError.emptyTranscript
        }
        guard isBounded(engineName, maximum: 128),
              configuredModel.map({
                  $0.count <= 256
              }) ?? true,
              engineModel.map({
                  $0.count <= 256
              }) ?? true else {
            throw VoiceContractError.invalidEngine
        }
        guard finiteNonNegative(inferenceMilliseconds),
              finiteNonNegative(finishMilliseconds) else {
            throw VoiceContractError.invalidTiming
        }

        let route = VoiceContractRoute(engineRoute)
        let retention = VoiceContractRetention(
            transcript: transcriptRetention
        )
        let request = VoiceContractRequestV1(
            schemaVersion: "voice-request.v1",
            requestId: requestId.uuidString.lowercased(),
            profileId: profileId,
            origin: .localVoiceMacOS,
            audio: audio,
            languagePolicy: VoiceContractLanguagePolicy(
                requested: requestedLanguage,
                allowDetection: requestedLanguage == "auto"
            ),
            enginePolicy: VoiceContractEnginePolicy(
                preference: VoiceContractEnginePreference(enginePreference),
                model: VoiceContractNullableString(configuredModel),
                keepWarm: keepWarm
            ),
            promptVocabulary: boundedVocabulary(promptVocabulary),
            maximumDurationMs: maximumDurationMilliseconds,
            retention: retention
        )
        let total = inferenceMilliseconds + finishMilliseconds
        let egress: VoiceContractNetworkEgress =
            route == .localLoopback ? .loopbackOnly : .none
        let response = VoiceContractResponseV1(
            schemaVersion: "voice-response.v1",
            requestId: request.requestId,
            profileId: profileId,
            origin: .localVoiceMacOS,
            transcript: VoiceContractTranscript(
                raw: VoiceContractNullableString(rawTranscript),
                normalized: normalized
            ),
            engine: VoiceContractEngine(
                name: engineName,
                model: VoiceContractNullableString(engineModel),
                route: route,
                persistent: enginePersistent
            ),
            language: VoiceContractLanguage(
                requested: requestedLanguage,
                detected: VoiceContractNullableString(detectedLanguage)
            ),
            timing: VoiceContractTiming(
                audioMs: Double(audio.durationMs),
                inferenceMs: inferenceMilliseconds,
                finishMs: finishMilliseconds,
                totalMs: total
            ),
            warnings: [],
            privacy: VoiceContractPrivacy(
                route: route,
                audioRetained: false,
                transcriptRetention: transcriptRetention,
                networkEgress: egress
            ),
            diagnostics: VoiceContractDiagnostics(
                realtimeFactor: audio.durationMs > 0
                    ? inferenceMilliseconds / Double(audio.durationMs)
                    : 0
            )
        )
        return VoiceContractPair(request: request, response: response)
    }

    public static func samplePair() throws -> VoiceContractPair {
        try makePair(
            requestId: UUID(
                uuidString: "7ec5a554-5804-4c52-a837-428e1f65c16d"
            )!,
            profileId: .generalDefault,
            audio: VoiceContractAudio(
                byteLength: 192_044,
                durationMs: 6_000
            ),
            requestedLanguage: "auto",
            detectedLanguage: "en",
            enginePreference: .auto,
            configuredModel: "parakeet-tdt-0.6b-v3",
            keepWarm: true,
            promptVocabulary: ["CipherOS", "Exploit Poker"],
            maximumDurationMilliseconds: 300_000,
            rawTranscript: "lets ship the voice platform",
            normalizedTranscript: "Let's ship the voice platform.",
            engineName: "parakeet-mlx",
            engineModel: "parakeet-tdt-0.6b-v3",
            engineRoute: .localProcess,
            enginePersistent: true,
            inferenceMilliseconds: 246,
            finishMilliseconds: 31,
            transcriptRetention: .localHistory
        )
    }

    private static func boundedVocabulary(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty else { continue }
            let bounded = String(trimmed.prefix(128))
            guard seen.insert(bounded).inserted else { continue }
            result.append(bounded)
            if result.count == 256 { break }
        }
        return result
    }

    private static func finiteNonNegative(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }

    private static func isBounded(
        _ value: String,
        maximum: Int
    ) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.count <= maximum
    }
}

private enum VoiceContractError: LocalizedError {
    case unsupportedAudio
    case productProfileMismatch
    case invalidAudioBounds
    case invalidLanguage
    case emptyTranscript
    case invalidEngine
    case invalidTiming

    var errorDescription: String? {
        switch self {
        case .unsupportedAudio:
            return "Voice contract requires mono 16 kHz PCM-16 WAV audio"
        case .productProfileMismatch:
            return "Local Voice cannot emit the poker.exploit profile"
        case .invalidAudioBounds:
            return "Voice contract audio exceeds the selected profile bounds"
        case .invalidLanguage:
            return "Voice contract language policy is invalid"
        case .emptyTranscript:
            return "Voice contract normalized transcript is empty"
        case .invalidEngine:
            return "Voice contract engine receipt is invalid"
        case .invalidTiming:
            return "Voice contract timing must be finite and non-negative"
        }
    }
}
