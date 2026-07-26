import Foundation

public class Transcriber {
    public var name: String { "whisper-cli (\(modelSize))" }
    public var modelName: String? { modelSize }
    public let executionRoute = STTExecutionRoute.localProcess
    public let modelSize: String
    private let language: String
    public var spokenPunctuation: Bool = false
    public var initialPrompt: String?

    public init(modelSize: String = "base.en", language: String = "en") {
        self.modelSize = modelSize
        self.language = language
    }

    public func transcribe(audioURL: URL) throws -> String {
        guard let whisperPath = Transcriber.findWhisperBinary() else {
            throw TranscriberError.whisperNotFound
        }

        guard let modelPath = Transcriber.findModel(modelSize: modelSize) else {
            throw TranscriberError.modelNotFound(modelSize)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        var args = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-l", language,
            "--no-timestamps",
            "-nt",
        ]
        if spokenPunctuation {
            args += ["--suppress-regex", "[,\\.\\?!;:\\-—]"]
        }
        if let prompt = initialPrompt, !prompt.isEmpty {
            args += ["--prompt", prompt]
        }
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        var stderrData = Data()
        let stderrThread = Thread {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        stderrThread.start()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        while !stderrThread.isFinished { Thread.sleep(forTimeInterval: 0.01) }
        process.waitUntilExit()

        let output = Transcriber.stripWhisperMarkers(
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )

        if process.terminationStatus != 0 {
            let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stderr.isEmpty { fputs("whisper-cpp: \(stderr)\n", Foundation.stderr) }
            throw TranscriberError.transcriptionFailed
        }

        return output
    }

    public func isAvailable() -> Bool {
        Self.findWhisperBinary() != nil && Self.findModel(modelSize: modelSize) != nil
    }

    public func warmup() {
        WhisperWarmKeeper.warmup(transcriber: self)
    }

    private static let knownMarkers: Set<String> = [
        "BLANK_AUDIO", "blank_audio",
        "Music", "MUSIC", "music",
        "Applause", "APPLAUSE", "applause",
        "Laughter", "LAUGHTER", "laughter",
        "silence", "Silence", "SILENCE",
        "SOUND", "Sound", "sound",
        "NOISE", "Noise", "noise",
        "INAUDIBLE", "inaudible",
    ]

    private static let markerRegex = try! NSRegularExpression(
        pattern: "[\\[\\(]\\s*([^\\]\\)]+?)\\s*[\\]\\)]"
    )

    public static func stripWhisperMarkers(_ text: String) -> String {
        let nsText = text as NSString
        let matches = markerRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var result = text
        for match in matches.reversed() {
            let innerRange = match.range(at: 1)
            let inner = nsText.substring(with: innerRange)
            if knownMarkers.contains(inner) {
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: "")
            }
        }
        return result
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func findWhisperBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        for name in ["whisper-cli", "whisper-cpp"] {
            let which = Process()
            which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            which.arguments = [name]
            let pipe = Pipe()
            which.standardOutput = pipe
            which.standardError = Pipe()
            try? which.run()
            which.waitUntilExit()

            let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let result = result, !result.isEmpty {
                return result
            }
        }

        return nil
    }

    public static func modelExists(modelSize: String) -> Bool {
        return findModel(modelSize: modelSize) != nil
    }

    static func findModel(modelSize: String) -> String? {
        for path in modelSearchPaths(modelSize: modelSize) {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    static func modelSearchPaths(
        modelSize: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        configDirectory: URL = Config.configDir,
        resourceDirectory: URL? = Bundle.main.resourceURL
    ) -> [String] {
        let modelFileName = "ggml-\(modelSize).bin"
        var candidates = [
            configDirectory
                .appendingPathComponent("models/\(modelFileName)")
                .path,
            homeDirectory
                .appendingPathComponent(
                    ".config/open-wispr/models/\(modelFileName)"
                )
                .path,
            homeDirectory
                .appendingPathComponent(
                    ".cache/whisper-cpp/\(modelFileName)"
                )
                .path,
            homeDirectory
                .appendingPathComponent(".cache/whisper/\(modelFileName)")
                .path,
            "/opt/homebrew/share/whisper-cpp/models/\(modelFileName)",
            "/usr/local/share/whisper-cpp/models/\(modelFileName)",
        ]
        if let resourceDirectory {
            candidates.insert(
                resourceDirectory
                    .appendingPathComponent("models/\(modelFileName)")
                    .path,
                at: 1
            )
        }
        return candidates
    }
}

extension Transcriber: STTEngine {}

enum TranscriberError: LocalizedError {
    case whisperNotFound
    case modelNotFound(String)
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .whisperNotFound:
            return "whisper-cpp not found. Install it with: brew install whisper-cpp"
        case .modelNotFound(let size):
            return "Whisper model '\(size)' not found. Download it with: local-voice download-model \(size)"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}
