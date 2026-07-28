import AVFoundation
import Dispatch
import Foundation

public struct LongFormLatencyBenchmarkReport: Codable, Sendable {
    public let schemaVersion: String
    public let generatedAt: String
    public let audioSource: String
    public let audioMilliseconds: Double
    public let transcriptCharacters: Int
    public let engine: String
    public let route: String
    public let inferenceMilliseconds: Double
    public let cleanupRoute: String
    public let cleanupMilliseconds: Double
    public let totalMilliseconds: Double
    public let targetMilliseconds: Double
    public let passed: Bool
    public let limitations: [String]
}

/// Fixture-backed reproduction for the slow long-dictation release path.
///
/// The report intentionally omits transcript content. It validates a warm
/// local engine plus the adaptive cleanup decision that runs after a user
/// releases the hotkey.
public enum LongFormLatencyBenchmark {
    public static func run(
        preferredEngine: STTEngineKind,
        modelSize: String,
        language: String
    ) throws -> LongFormLatencyBenchmarkReport {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "local-voice-long-form-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: temporaryDirectory
            )
        }

        let paragraph = """
        Local Voice keeps every stage on this computer. The warm speech engine \
        turns a long explanation into punctuated text, while the interface \
        remains responsive and the active application never loses focus. \
        A bounded cleanup policy returns long-form dictation immediately \
        instead of asking a second model to regenerate the entire transcript.
        """
        let fixtureText = Array(
            repeating: paragraph,
            count: 7
        ).joined(separator: " ")
        let aiff = temporaryDirectory.appendingPathComponent("long-form.aiff")
        let wav = temporaryDirectory.appendingPathComponent("long-form.wav")
        try VoiceBenchmark.runProcess(
            executable: "/usr/bin/say",
            arguments: ["-r", "175", "-o", aiff.path, fixtureText],
            timeoutSeconds: 30
        )
        try VoiceBenchmark.runProcess(
            executable: "/usr/bin/afconvert",
            arguments: [
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
                aiff.path,
                wav.path,
            ],
            timeoutSeconds: 30
        )

        let audio = try AVAudioFile(forReading: wav)
        guard audio.processingFormat.sampleRate > 0 else {
            throw LongFormLatencyBenchmarkError.invalidAudio
        }
        let audioMilliseconds =
            Double(audio.length)
            / audio.processingFormat.sampleRate
            * 1_000

        let router = STTRouter(
            language: language,
            modelSize: modelSize,
            preferredEngine: preferredEngine
        )
        defer { router.shutdown() }
        router.warmup()

        let inferenceStart = DispatchTime.now().uptimeNanoseconds
        let transcript = try router.transcribe(audioURL: wav)
        let inferenceMilliseconds = elapsedMilliseconds(
            since: inferenceStart
        )

        let cleanupStart = DispatchTime.now().uptimeNanoseconds
        let cleanupRoute = DictationCleanupPolicy.route(
            enabled: true,
            characterCount: transcript.count,
            recordingMilliseconds: audioMilliseconds
        )
        let cleanupMilliseconds = elapsedMilliseconds(
            since: cleanupStart
        )
        let totalMilliseconds =
            inferenceMilliseconds + cleanupMilliseconds
        let targetMilliseconds = 5_000.0
        let passed =
            cleanupRoute == .fastLongForm
            && totalMilliseconds <= targetMilliseconds

        return LongFormLatencyBenchmarkReport(
            schemaVersion: "local-voice-long-form-latency.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            audioSource:
                "macOS system text-to-speech; repeated public fixture; mono PCM WAV at 16 kHz",
            audioMilliseconds: audioMilliseconds,
            transcriptCharacters: transcript.count,
            engine: router.activeEngineName(),
            route: router.activeExecutionRoute().rawValue,
            inferenceMilliseconds: inferenceMilliseconds,
            cleanupRoute: cleanupRoute.rawValue,
            cleanupMilliseconds: cleanupMilliseconds,
            totalMilliseconds: totalMilliseconds,
            targetMilliseconds: targetMilliseconds,
            passed: passed,
            limitations: [
                "Synthetic text-to-speech is a repeatable latency fixture, not a human-microphone accuracy claim.",
                "The benchmark measures a warm local engine and does not include cursor insertion.",
                "Physical long-form dictation remains an operator acceptance check.",
            ]
        )
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Double {
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000
    }
}

private enum LongFormLatencyBenchmarkError: LocalizedError {
    case invalidAudio

    var errorDescription: String? {
        "Could not measure the long-form latency fixture"
    }
}
