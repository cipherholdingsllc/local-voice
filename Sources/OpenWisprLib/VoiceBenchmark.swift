import AVFoundation
import Darwin
import Dispatch
import Foundation

public struct VoiceBenchmarkSample: Codable, Sendable {
    public let id: String
    public let reference: String
    public let transcript: String
    public let engine: String
    public let route: String
    public let audioMilliseconds: Double
    public let finishMilliseconds: Double
    public let wordErrors: Int
    public let referenceWords: Int

    public var wordErrorRate: Double {
        guard referenceWords > 0 else { return 0 }
        return Double(wordErrors) / Double(referenceWords)
    }
}

public struct VoiceBenchmarkAggregate: Codable, Sendable {
    public let sampleCount: Int
    public let totalReferenceWords: Int
    public let totalWordErrors: Int
    public let wordErrorRate: Double
    public let medianFinishMilliseconds: Double
    public let p95FinishMilliseconds: Double
    public let meanRealtimeFactor: Double
    public let latencyTargetMilliseconds: Double
    public let wordErrorRateTarget: Double
    public let passed: Bool
}

public struct VoiceBenchmarkReport: Codable, Sendable {
    public let schemaVersion: String
    public let generatedAt: String
    public let corpus: String
    public let audioSource: String
    public let enginePreference: String
    public let configuredModel: String
    public let language: String
    public let coldStartMilliseconds: Double
    public let samples: [VoiceBenchmarkSample]
    public let aggregate: VoiceBenchmarkAggregate
    public let limitations: [String]
}

public enum VoiceBenchmark {
    public static let corpus: [(id: String, text: String)] = [
        (
            "LV-B01",
            "Local Voice keeps speech processing private and responsive."
        ),
        (
            "LV-B02",
            "Draft a concise follow-up for tomorrow morning."
        ),
        (
            "LV-B03",
            "The API returns a JSON response over local loopback."
        ),
        (
            "LV-B04",
            "Run git status before committing the changed files."
        ),
        (
            "LV-B05",
            "Exploit Poker uses a three-bet and check-raise vocabulary."
        ),
        (
            "LV-B06",
            "The effective stack is one hundred big blinds."
        ),
        (
            "LV-B07",
            "CipherOS rejects untrusted origins and oversized payloads."
        ),
        (
            "LV-B08",
            "Send the technical brief after lunch."
        ),
    ]

    public static func run(
        preferredEngine: STTEngineKind,
        modelSize: String,
        language: String
    ) throws -> VoiceBenchmarkReport {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "local-voice-benchmark-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fixtures = try corpus.map { item in
            let aiff = temporaryDirectory.appendingPathComponent("\(item.id).aiff")
            let wav = temporaryDirectory.appendingPathComponent("\(item.id).wav")
            try runProcess(
                executable: "/usr/bin/say",
                arguments: ["-o", aiff.path, item.text]
            )
            try runProcess(
                executable: "/usr/bin/afconvert",
                arguments: [
                    "-f", "WAVE",
                    "-d", "LEI16@16000",
                    "-c", "1",
                    aiff.path,
                    wav.path,
                ]
            )
            return (item: item, url: wav)
        }

        let router = STTRouter(
            language: language,
            modelSize: modelSize,
            preferredEngine: preferredEngine
        )
        defer { router.shutdown() }

        let coldStart = DispatchTime.now().uptimeNanoseconds
        router.warmup()
        let coldStartMilliseconds = elapsedMilliseconds(since: coldStart)

        var samples: [VoiceBenchmarkSample] = []
        for fixture in fixtures {
            let duration = try audioDurationMilliseconds(url: fixture.url)
            let started = DispatchTime.now().uptimeNanoseconds
            let transcript = try router.transcribe(audioURL: fixture.url)
            let finishMilliseconds = elapsedMilliseconds(since: started)
            let referenceTokens = tokens(fixture.item.text)
            let transcriptTokens = tokens(transcript)
            let errors = editDistance(referenceTokens, transcriptTokens)
            samples.append(
                VoiceBenchmarkSample(
                    id: fixture.item.id,
                    reference: fixture.item.text,
                    transcript: transcript,
                    engine: router.activeEngineName(),
                    route: router.activeExecutionRoute().rawValue,
                    audioMilliseconds: duration,
                    finishMilliseconds: finishMilliseconds,
                    wordErrors: errors,
                    referenceWords: referenceTokens.count
                )
            )
        }

        let totalWords = samples.reduce(0) { $0 + $1.referenceWords }
        let totalErrors = samples.reduce(0) { $0 + $1.wordErrors }
        let wordErrorRate = totalWords == 0
            ? 0
            : Double(totalErrors) / Double(totalWords)
        let latencies = samples.map(\.finishMilliseconds)
        let median = percentile(latencies, fraction: 0.50)
        let p95 = percentile(latencies, fraction: 0.95)
        let realtimeFactors = samples.compactMap { sample -> Double? in
            guard sample.audioMilliseconds > 0 else { return nil }
            return sample.finishMilliseconds / sample.audioMilliseconds
        }
        let meanRealtimeFactor = realtimeFactors.isEmpty
            ? 0
            : realtimeFactors.reduce(0, +) / Double(realtimeFactors.count)
        let latencyTarget = 1_000.0
        let wordErrorTarget = 0.15

        return VoiceBenchmarkReport(
            schemaVersion: "local-voice-benchmark.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            corpus: "LV-B01...LV-B08",
            audioSource: "macOS system text-to-speech; mono PCM WAV at 16 kHz",
            enginePreference: preferredEngine.rawValue,
            configuredModel: modelSize,
            language: language,
            coldStartMilliseconds: coldStartMilliseconds,
            samples: samples,
            aggregate: VoiceBenchmarkAggregate(
                sampleCount: samples.count,
                totalReferenceWords: totalWords,
                totalWordErrors: totalErrors,
                wordErrorRate: wordErrorRate,
                medianFinishMilliseconds: median,
                p95FinishMilliseconds: p95,
                meanRealtimeFactor: meanRealtimeFactor,
                latencyTargetMilliseconds: latencyTarget,
                wordErrorRateTarget: wordErrorTarget,
                passed: p95 <= latencyTarget && wordErrorRate <= wordErrorTarget
            ),
            limitations: [
                "Synthetic text-to-speech is a repeatable regression fixture, not a human-microphone accuracy claim.",
                "The benchmark does not test accents, background noise, microphone hardware, cursor insertion, or packet-level network isolation.",
                "A physical-device benchmark is still required for the iPhone engine.",
            ]
        )
    }

    static func tokens(_ text: String) -> [String] {
        let folded = text
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar)
                ? Character(String(scalar))
                : " "
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        for (leftIndex, left) in lhs.enumerated() {
            var current = Array(repeating: 0, count: rhs.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, right) in rhs.enumerated() {
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + (left == right ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }

    static func percentile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let bounded = min(1, max(0, fraction))
        let rank = max(0, Int(ceil(bounded * Double(sorted.count))) - 1)
        return sorted[rank]
    }

    private static func audioDurationMilliseconds(url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate > 0 else {
            throw VoiceBenchmarkError.invalidAudio(url.path)
        }
        return Double(file.length) / file.processingFormat.sampleRate * 1000
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Double {
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000
    }

    static func runProcess(
        executable: String,
        arguments: [String],
        timeoutSeconds: Double = 15
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        try process.run()

        let timeoutMilliseconds = max(
            1,
            Int((timeoutSeconds * 1_000).rounded(.up))
        )
        if completion.wait(
            timeout: .now() + .milliseconds(timeoutMilliseconds)
        ) == .timedOut {
            let pid = process.processIdentifier
            if process.isRunning {
                process.terminate()
            }
            if completion.wait(timeout: .now() + .seconds(1)) == .timedOut {
                _ = Darwin.kill(pid, SIGKILL)
                _ = completion.wait(timeout: .now() + .seconds(1))
            }
            throw VoiceBenchmarkError.processTimedOut(
                executable,
                timeoutSeconds
            )
        }

        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw VoiceBenchmarkError.processFailed(
                executable,
                process.terminationStatus,
                detail
            )
        }
    }
}

private enum VoiceBenchmarkError: LocalizedError {
    case invalidAudio(String)
    case processFailed(String, Int32, String)
    case processTimedOut(String, Double)

    var errorDescription: String? {
        switch self {
        case .invalidAudio(let path):
            return "Could not measure benchmark audio at \(path)"
        case .processFailed(let executable, let status, let detail):
            let suffix = detail.isEmpty ? "" : ": \(detail)"
            return "\(executable) failed with status \(status)\(suffix)"
        case .processTimedOut(let executable, let seconds):
            return "\(executable) exceeded the \(seconds)-second benchmark fixture timeout"
        }
    }
}
