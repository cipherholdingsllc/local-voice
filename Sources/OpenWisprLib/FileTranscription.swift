import AppKit
import Darwin
import Foundation

public enum FileTranscriptionStatus: String, Codable, Sendable {
    case queued
    case normalizing
    case transcribing
    case completed
    case failed
    case cancelled

    public var isActive: Bool {
        self == .normalizing || self == .transcribing
    }

    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

public enum FileTranscriptFormat: String, CaseIterable, Codable, Sendable {
    case text = "txt"
    case markdown = "md"
    case json
    case srt
    case vtt

    public var label: String {
        switch self {
        case .text: return "Plain text"
        case .markdown: return "Markdown"
        case .json: return "JSON receipt"
        case .srt: return "SRT captions"
        case .vtt: return "WebVTT captions"
        }
    }
}

public struct FileTranscriptSegment: Codable, Equatable, Sendable {
    public let index: Int
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    public let rawText: String
    public let text: String
    public let engineName: String
    public let modelName: String?
    public let route: String
    public let inferenceMilliseconds: Double
    public let contractPair: VoiceContractPair?

    public init(
        index: Int,
        startMilliseconds: Int,
        endMilliseconds: Int,
        rawText: String,
        text: String,
        engineName: String,
        modelName: String?,
        route: String,
        inferenceMilliseconds: Double,
        contractPair: VoiceContractPair? = nil
    ) {
        self.index = index
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.rawText = rawText
        self.text = text
        self.engineName = engineName
        self.modelName = modelName
        self.route = route
        self.inferenceMilliseconds = inferenceMilliseconds
        self.contractPair = contractPair
    }
}

public struct FileTranscriptionJob: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let filename: String
    public let fileExtension: String
    public var status: FileTranscriptionStatus
    public var progress: Double
    public var durationMilliseconds: Int
    public var transcript: String
    public var engineSummary: String
    public var routeSummary: String
    public var segments: [FileTranscriptSegment]
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        filename: String,
        fileExtension: String,
        status: FileTranscriptionStatus = .queued,
        progress: Double = 0,
        durationMilliseconds: Int = 0,
        transcript: String = "",
        engineSummary: String = "",
        routeSummary: String = "",
        segments: [FileTranscriptSegment] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.filename = filename
        self.fileExtension = fileExtension
        self.status = status
        self.progress = progress
        self.durationMilliseconds = durationMilliseconds
        self.transcript = transcript
        self.engineSummary = engineSummary
        self.routeSummary = routeSummary
        self.segments = segments
        self.errorMessage = errorMessage
    }

    public var wordCount: Int {
        transcript.split(whereSeparator: \.isWhitespace).count
    }
}

public struct FileTranscriptionResult: Equatable, Sendable {
    public let durationMilliseconds: Int
    public let transcript: String
    public let engineSummary: String
    public let routeSummary: String
    public let segments: [FileTranscriptSegment]
}

public protocol FileTranscriptionProcessing: AnyObject {
    func process(
        url: URL,
        progress: @escaping (
            FileTranscriptionStatus,
            Double
        ) -> Bool
    ) throws -> FileTranscriptionResult
}

public final class FileTranscriptionStore: ObservableObject {
    public static let shared = FileTranscriptionStore(
        processor: LocalFileTranscriptionProcessor(
            preserveSharedParakeet: true
        ),
        persistenceEnabled:
            Config.load().saveTranscriptHistory?.value ?? true
    )

    @Published public private(set) var jobs: [FileTranscriptionJob]

    private let storageURL: URL?
    private let maximumJobs: Int
    private let retentionDays: Int
    private var persistenceEnabled: Bool
    private let processor: FileTranscriptionProcessing?
    private let processingQueue = DispatchQueue(
        label: "com.cipherholdings.localvoice.file-transcription",
        qos: .userInitiated
    )
    private let cancellationLock = NSLock()
    private var cancelledIDs = Set<UUID>()
    private var sourceURLs: [UUID: URL] = [:]
    private var activeID: UUID?

    public init(
        storageURL: URL? = Config.configDir
            .appendingPathComponent("file-history.json"),
        jobs: [FileTranscriptionJob]? = nil,
        processor: FileTranscriptionProcessing? = nil,
        persistenceEnabled: Bool = true,
        failInterruptedJobs: Bool = true,
        maximumJobs: Int = 100,
        retentionDays: Int? = nil
    ) {
        self.storageURL = storageURL
        self.maximumJobs = max(1, maximumJobs)
        self.retentionDays = max(
            1,
            min(
                retentionDays
                    ?? Config.load().historyRetentionDays
                    ?? 30,
                365
            )
        )
        self.persistenceEnabled = persistenceEnabled
        self.processor = processor

        if let jobs {
            self.jobs = jobs
        } else if let storageURL,
                  let data = try? Data(contentsOf: storageURL),
                  let decoded = try? JSONDecoder.fileTranscription.decode(
                      [FileTranscriptionJob].self,
                      from: data
                  ) {
            self.jobs = decoded
        } else {
            self.jobs = []
        }

        if failInterruptedJobs {
            for index in self.jobs.indices
                where !self.jobs[index].status.isTerminal {
                self.jobs[index].status = .failed
                self.jobs[index].errorMessage =
                    "Processing was interrupted before completion. Add the file again to retry."
            }
        }
        self.jobs.sort { $0.createdAt > $1.createdAt }
        pruneHistory()
    }

    public var activeCount: Int {
        jobs.filter { $0.status.isActive || $0.status == .queued }.count
    }

    public var completedCount: Int {
        jobs.filter { $0.status == .completed }.count
    }

    public func enqueue(urls: [URL]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.enqueue(urls: urls)
            }
            return
        }

        for url in urls {
            let ext = url.pathExtension.lowercased()
            var job = FileTranscriptionJob(
                filename: url.lastPathComponent,
                fileExtension: ext
            )
            guard AudioFileNormalizer.supports(url: url) else {
                job.status = .failed
                job.errorMessage =
                    "Unsupported file. Add WAV, AIFF, CAF, MP3, M4A, AAC, FLAC, OGG, WebM, MP4, MOV, or M4V."
                jobs.insert(job, at: 0)
                continue
            }
            sourceURLs[job.id] = url
            jobs.insert(job, at: 0)
        }
        pruneHistory()
        persist()
        processNextIfNeeded()
    }

    public func cancel(id: UUID) {
        cancellationLock.lock()
        cancelledIDs.insert(id)
        cancellationLock.unlock()

        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        if jobs[index].status == .queued {
            jobs[index].status = .cancelled
            jobs[index].errorMessage = nil
            sourceURLs[id] = nil
            persist()
            processNextIfNeeded()
        }
    }

    public func exportData(
        for job: FileTranscriptionJob,
        format: FileTranscriptFormat
    ) throws -> Data {
        try FileTranscriptExporter.data(job: job, format: format)
    }

    public func setPersistenceEnabled(_ enabled: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.setPersistenceEnabled(enabled)
            }
            return
        }
        persistenceEnabled = enabled
    }

    public static func preview() -> FileTranscriptionStore {
        let segments = [
            FileTranscriptSegment(
                index: 1,
                startMilliseconds: 0,
                endMilliseconds: 18_200,
                rawText: "Today we agreed to keep the voice core local.",
                text: "Today we agreed to keep the voice core local.",
                engineName: "parakeet-tdt-0.6b",
                modelName: "parakeet-tdt-0.6b-v3",
                route: "local_process",
                inferenceMilliseconds: 188
            ),
            FileTranscriptSegment(
                index: 2,
                startMilliseconds: 18_200,
                endMilliseconds: 42_800,
                rawText: "The next review covers the iphone release path.",
                text: "The next review covers the iPhone release path.",
                engineName: "parakeet-tdt-0.6b",
                modelName: "parakeet-tdt-0.6b-v3",
                route: "local_process",
                inferenceMilliseconds: 214
            ),
        ]
        let complete = FileTranscriptionJob(
            createdAt: Date().addingTimeInterval(-26 * 60),
            filename: "Product review.m4a",
            fileExtension: "m4a",
            status: .completed,
            progress: 1,
            durationMilliseconds: 42_800,
            transcript: segments.map(\.text).joined(separator: " "),
            engineSummary: "Parakeet TDT v3",
            routeSummary: "Local process",
            segments: segments
        )
        let running = FileTranscriptionJob(
            createdAt: Date().addingTimeInterval(-2 * 60),
            filename: "Customer interview.mp3",
            fileExtension: "mp3",
            status: .transcribing,
            progress: 0.64,
            durationMilliseconds: 312_000,
            engineSummary: "Persistent Whisper",
            routeSummary: "Private loopback"
        )
        return FileTranscriptionStore(
            storageURL: nil,
            jobs: [running, complete],
            persistenceEnabled: false,
            failInterruptedJobs: false
        )
    }

    private func processNextIfNeeded() {
        precondition(Thread.isMainThread)
        guard activeID == nil, let processor else { return }
        guard let index = jobs.firstIndex(where: {
            $0.status == .queued && sourceURLs[$0.id] != nil
        }), let url = sourceURLs[jobs[index].id] else {
            return
        }

        let id = jobs[index].id
        activeID = id
        jobs[index].status = .normalizing
        jobs[index].progress = 0.01
        persist()

        processingQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try processor.process(
                    url: url,
                    progress: { [weak self] status, fraction in
                        guard let self else { return false }
                        if self.isCancelled(id) { return false }
                        DispatchQueue.main.async {
                            self.update(id: id) {
                                $0.status = status
                                $0.progress = min(0.99, max(0, fraction))
                            }
                        }
                        return true
                    }
                )
                DispatchQueue.main.async {
                    if self.isCancelled(id) {
                        self.finishCancelled(id: id)
                    } else {
                        self.update(id: id) {
                            $0.status = .completed
                            $0.progress = 1
                            $0.durationMilliseconds =
                                result.durationMilliseconds
                            $0.transcript = result.transcript
                            $0.engineSummary = result.engineSummary
                            $0.routeSummary = result.routeSummary
                            $0.segments = result.segments
                            $0.errorMessage = nil
                        }
                        self.finish(id: id)
                    }
                }
            } catch FileTranscriptionError.cancelled {
                DispatchQueue.main.async {
                    self.finishCancelled(id: id)
                }
            } catch {
                DispatchQueue.main.async {
                    self.update(id: id) {
                        $0.status = .failed
                        $0.errorMessage = error.localizedDescription
                    }
                    self.finish(id: id)
                }
            }
        }
    }

    private func update(
        id: UUID,
        _ transform: (inout FileTranscriptionJob) -> Void
    ) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        transform(&jobs[index])
        persist()
    }

    private func finishCancelled(id: UUID) {
        update(id: id) {
            $0.status = .cancelled
            $0.errorMessage = nil
        }
        finish(id: id)
    }

    private func finish(id: UUID) {
        sourceURLs[id] = nil
        cancellationLock.lock()
        cancelledIDs.remove(id)
        cancellationLock.unlock()
        if activeID == id { activeID = nil }
        persist()
        processNextIfNeeded()
    }

    private func isCancelled(_ id: UUID) -> Bool {
        cancellationLock.lock()
        defer { cancellationLock.unlock() }
        return cancelledIDs.contains(id)
    }

    private func persist() {
        guard persistenceEnabled, let storageURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.fileTranscription.encode(jobs)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            fputs(
                "File transcript history could not be saved: \(error.localizedDescription)\n",
                stderr
            )
        }
    }

    private func pruneHistory() {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date()
        )
        if let cutoff {
            jobs.removeAll {
                $0.status.isTerminal && $0.createdAt < cutoff
            }
        }
        guard jobs.count > maximumJobs else { return }
        var index = jobs.count - 1
        while jobs.count > maximumJobs, index >= 0 {
            if jobs[index].status.isTerminal {
                sourceURLs[jobs[index].id] = nil
                jobs.remove(at: index)
            }
            index -= 1
        }
    }
}

public final class LocalFileTranscriptionProcessor:
    FileTranscriptionProcessing {
    private let normalizer: AudioFileNormalizer
    private let preserveSharedParakeet: Bool

    public init(
        normalizer: AudioFileNormalizer = AudioFileNormalizer(),
        preserveSharedParakeet: Bool = false
    ) {
        self.normalizer = normalizer
        self.preserveSharedParakeet = preserveSharedParakeet
    }

    public func process(
        url: URL,
        progress: @escaping (
            FileTranscriptionStatus,
            Double
        ) -> Bool
    ) throws -> FileTranscriptionResult {
        guard progress(.normalizing, 0.02) else {
            throw FileTranscriptionError.cancelled
        }
        let batch = try normalizer.normalize(url: url)
        defer { batch.cleanup() }
        guard progress(.transcribing, 0.08) else {
            throw FileTranscriptionError.cancelled
        }

        let config = Config.load()
        let prompt = VocabularyLearner.shared.promptString(
            configTerms: config.customVocabulary ?? []
        )
        let vocabulary = VocabularyLearner.shared.merged(
            with: config.customVocabulary ?? []
        )
        let router = STTRouter(
            language: config.language,
            modelSize: config.modelSize,
            preferredEngine: config.sttEngine ?? .auto,
            spokenPunctuation: config.spokenPunctuation?.value ?? false,
            initialPrompt: prompt.isEmpty ? nil : prompt
        )
        defer {
            router.shutdown(
                preserveParakeet: preserveSharedParakeet
            )
        }
        router.warmup()

        var segments: [FileTranscriptSegment] = []
        for (offset, chunk) in batch.chunks.enumerated() {
            guard progress(
                .transcribing,
                0.08 + 0.9 * Double(offset) / Double(batch.chunks.count)
            ) else {
                throw FileTranscriptionError.cancelled
            }

            let audio = try LocalVoiceContract.audioDescriptor(for: chunk)
            let start = Date()
            let raw = try router.transcribe(audioURL: chunk)
            let inference = Date().timeIntervalSince(start) * 1_000
            var text = (config.spokenPunctuation?.value ?? false)
                ? TextPostProcessor.process(raw)
                : raw.trimmingCharacters(in: .whitespacesAndNewlines)
            text = VocabularyLearner.shared.postProcess(
                text,
                configTerms: config.customVocabulary ?? []
            )
            guard !text.isEmpty else { continue }

            let startMilliseconds = offset
                * AudioFileNormalizer.segmentMilliseconds
            let endMilliseconds = min(
                batch.durationMilliseconds,
                startMilliseconds + audio.durationMs
            )
            let route = router.activeExecutionRoute()
            let contract = try? LocalVoiceContract.makePair(
                requestId: UUID(),
                profileId: .generalDefault,
                audio: audio,
                requestedLanguage: config.language,
                detectedLanguage: nil,
                enginePreference: config.sttEngine ?? .auto,
                configuredModel: config.modelSize,
                keepWarm: true,
                promptVocabulary: vocabulary,
                maximumDurationMilliseconds:
                    VoiceContractProfileID.generalDefault
                        .maximumDurationMilliseconds,
                rawTranscript: raw,
                normalizedTranscript: text,
                engineName: router.activeEngineName(),
                engineModel: router.activeEngineModelName(),
                engineRoute: route,
                enginePersistent: router.activeEngineIsPersistent(),
                inferenceMilliseconds: inference,
                finishMilliseconds: 0,
                transcriptRetention: .localHistory
            )
            segments.append(
                FileTranscriptSegment(
                    index: segments.count + 1,
                    startMilliseconds: startMilliseconds,
                    endMilliseconds: endMilliseconds,
                    rawText: raw,
                    text: text,
                    engineName: router.activeEngineName(),
                    modelName: router.activeEngineModelName(),
                    route: route.rawValue,
                    inferenceMilliseconds: inference,
                    contractPair: contract
                )
            )
        }

        guard !segments.isEmpty else {
            throw FileTranscriptionError.noSpeech
        }
        _ = progress(.transcribing, 0.99)

        let engines = orderedUnique(segments.map(\.engineName))
        let routes = orderedUnique(segments.map(\.route))
        return FileTranscriptionResult(
            durationMilliseconds: batch.durationMilliseconds,
            transcript: segments.map(\.text).joined(separator: " "),
            engineSummary: engines.joined(separator: " + "),
            routeSummary: routes.map(routeLabel).joined(separator: " + "),
            segments: segments
        )
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func routeLabel(_ route: String) -> String {
        switch route {
        case STTExecutionRoute.localLoopback.rawValue:
            return "Private loopback"
        case STTExecutionRoute.localProcess.rawValue:
            return "Local process"
        default:
            return route
        }
    }
}

public struct NormalizedAudioBatch {
    public let directory: URL
    public let chunks: [URL]
    public let durationMilliseconds: Int

    public func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

public struct AudioFileNormalizer {
    public static let segmentMilliseconds = 30_000
    public static let maximumDurationSeconds: Double = 4 * 60 * 60
    public static let maximumSourceBytes: UInt64 = 8 * 1_024 * 1_024 * 1_024

    private static let supportedExtensions: Set<String> = [
        "wav", "aif", "aiff", "caf", "mp3", "m4a", "aac",
        "flac", "ogg", "webm", "mp4", "mov", "m4v",
    ]

    public init() {}

    public static func supports(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public static func findFFmpeg() -> String? {
        executable(
            named: "ffmpeg",
            candidates: [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
            ]
        )
    }

    public static func findFFprobe() -> String? {
        executable(
            named: "ffprobe",
            candidates: [
                "/opt/homebrew/bin/ffprobe",
                "/usr/local/bin/ffprobe",
            ]
        )
    }

    public func normalize(url: URL) throws -> NormalizedAudioBatch {
        guard Self.supports(url: url) else {
            throw FileTranscriptionError.unsupportedFile
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileTranscriptionError.fileMissing
        }
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard values.isRegularFile == true else {
            throw FileTranscriptionError.fileMissing
        }
        let sourceBytes = UInt64(max(0, values.fileSize ?? 0))
        guard sourceBytes <= Self.maximumSourceBytes else {
            throw FileTranscriptionError.fileTooLarge
        }
        guard let ffmpeg = Self.findFFmpeg(),
              let ffprobe = Self.findFFprobe() else {
            throw FileTranscriptionError.ffmpegMissing
        }

        let probedDuration = try probeDuration(
            url: url,
            ffprobe: ffprobe
        )
        guard probedDuration > 0,
              probedDuration <= Self.maximumDurationSeconds else {
            throw FileTranscriptionError.durationOutOfBounds
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "local-voice-file-\(UUID().uuidString)",
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let pattern = directory
                .appendingPathComponent("segment-%05d.wav")
                .path
            _ = try FileProcessRunner.run(
                executable: ffmpeg,
                arguments: [
                    "-nostdin",
                    "-hide_banner",
                    "-loglevel", "error",
                    "-i", url.path,
                    "-map", "0:a:0",
                    "-vn",
                    "-ac", "1",
                    "-ar", "16000",
                    "-c:a", "pcm_s16le",
                    "-f", "segment",
                    "-segment_time",
                    String(Double(Self.segmentMilliseconds) / 1_000),
                    "-reset_timestamps", "1",
                    "-segment_format", "wav",
                    pattern,
                ],
                timeout: 10 * 60
            )
            let chunks = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !chunks.isEmpty else {
                throw FileTranscriptionError.noAudioTrack
            }
            let duration = try chunks.reduce(0) {
                $0 + (try LocalVoiceContract.audioDescriptor(for: $1))
                    .durationMs
            }
            guard duration <= Int(Self.maximumDurationSeconds * 1_000) else {
                throw FileTranscriptionError.durationOutOfBounds
            }
            return NormalizedAudioBatch(
                directory: directory,
                chunks: chunks,
                durationMilliseconds: duration
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func probeDuration(
        url: URL,
        ffprobe: String
    ) throws -> Double {
        let audioStream = try FileProcessRunner.run(
            executable: ffprobe,
            arguments: [
                "-v", "error",
                "-select_streams", "a:0",
                "-show_entries", "stream=index",
                "-of", "csv=p=0",
                url.path,
            ],
            timeout: 30
        )
        guard !audioStream.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw FileTranscriptionError.noAudioTrack
        }
        let output = try FileProcessRunner.run(
            executable: ffprobe,
            arguments: [
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                url.path,
            ],
            timeout: 30
        )
        guard let duration = Double(
            output.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            throw FileTranscriptionError.noAudioTrack
        }
        return duration
    }

    private static func executable(
        named name: String,
        candidates: [String]
    ) -> String? {
        for candidate in candidates
            where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let result = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result, !result.isEmpty else { return nil }
        return result
    }
}

public enum FileTranscriptExporter {
    public static func data(
        job: FileTranscriptionJob,
        format: FileTranscriptFormat
    ) throws -> Data {
        guard job.status == .completed, !job.transcript.isEmpty else {
            throw FileTranscriptionError.transcriptUnavailable
        }
        switch format {
        case .text:
            return Data((job.transcript + "\n").utf8)
        case .markdown:
            let body = """
            # \(job.filename)

            Transcribed locally by Local Voice on \(job.createdAt.formatted(date: .abbreviated, time: .shortened)).

            \(job.transcript)
            """
            return Data((body + "\n").utf8)
        case .json:
            let document = FileTranscriptDocument(job: job)
            return try JSONEncoder.fileTranscriptExport.encode(document)
        case .srt:
            return Data(captions(job: job, webVTT: false).utf8)
        case .vtt:
            return Data(captions(job: job, webVTT: true).utf8)
        }
    }

    private static func captions(
        job: FileTranscriptionJob,
        webVTT: Bool
    ) -> String {
        let body = job.segments.enumerated().map { offset, segment in
            let range = "\(timestamp(segment.startMilliseconds, webVTT: webVTT)) --> \(timestamp(segment.endMilliseconds, webVTT: webVTT))"
            if webVTT {
                return "\(range)\n\(segment.text)"
            }
            return "\(offset + 1)\n\(range)\n\(segment.text)"
        }
        .joined(separator: "\n\n")
        return webVTT ? "WEBVTT\n\n\(body)\n" : "\(body)\n"
    }

    static func timestamp(
        _ milliseconds: Int,
        webVTT: Bool
    ) -> String {
        let bounded = max(0, milliseconds)
        let hours = bounded / 3_600_000
        let minutes = (bounded / 60_000) % 60
        let seconds = (bounded / 1_000) % 60
        let millis = bounded % 1_000
        return String(
            format: "%02d:%02d:%02d%@%03d",
            hours,
            minutes,
            seconds,
            webVTT ? "." : ",",
            millis
        )
    }
}

private struct FileTranscriptDocument: Encodable {
    let schemaVersion: String
    let id: UUID
    let createdAt: Date
    let filename: String
    let durationMilliseconds: Int
    let transcript: String
    let engineSummary: String
    let routeSummary: String
    let segments: [FileTranscriptSegment]

    init(job: FileTranscriptionJob) {
        schemaVersion = "local-voice-file-transcript.v1"
        id = job.id
        createdAt = job.createdAt
        filename = job.filename
        durationMilliseconds = job.durationMilliseconds
        transcript = job.transcript
        engineSummary = job.engineSummary
        routeSummary = job.routeSummary
        segments = job.segments
    }
}

private enum FileProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "local-voice-process-\(UUID().uuidString).out"
            )
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "local-voice-process-\(UUID().uuidString).err"
            )
        FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil
        )
        FileManager.default.createFile(
            atPath: errorURL.path,
            contents: nil
        )
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        let output = try FileHandle(forWritingTo: outputURL)
        let error = try FileHandle(forWritingTo: errorURL)
        defer {
            try? output.close()
            try? error.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()

        if completed.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if completed.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = completed.wait(timeout: .now() + 1)
            }
            throw FileTranscriptionError.processTimedOut
        }
        try? output.synchronize()
        try? error.synchronize()
        let stdout = (try? String(
            contentsOf: outputURL,
            encoding: .utf8
        )) ?? ""
        let stderrText = (try? String(
            contentsOf: errorURL,
            encoding: .utf8
        )) ?? ""
        guard process.terminationStatus == 0 else {
            throw FileTranscriptionError.processFailed(
                stderrText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        }
        return stdout
    }
}

public enum FileTranscriptionError: LocalizedError {
    case unsupportedFile
    case fileMissing
    case fileTooLarge
    case durationOutOfBounds
    case ffmpegMissing
    case noAudioTrack
    case noSpeech
    case processTimedOut
    case processFailed(String)
    case transcriptUnavailable
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "This audio or video format is not supported."
        case .fileMissing:
            return "The selected file is no longer available."
        case .fileTooLarge:
            return "Files larger than 8 GB are not accepted."
        case .durationOutOfBounds:
            return "File duration must be greater than zero and no longer than four hours."
        case .ffmpegMissing:
            return "FFmpeg and FFprobe are required. Install them with: brew install ffmpeg"
        case .noAudioTrack:
            return "The selected file does not contain a readable audio track."
        case .noSpeech:
            return "No speech was detected in the selected file."
        case .processTimedOut:
            return "Audio preparation exceeded the ten-minute safety limit."
        case .processFailed(let detail):
            return detail.isEmpty
                ? "Audio preparation failed."
                : "Audio preparation failed: \(detail)"
        case .transcriptUnavailable:
            return "A completed transcript is required before export."
        case .cancelled:
            return "File transcription was cancelled."
        }
    }
}

private extension JSONEncoder {
    static var fileTranscription: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var fileTranscriptExport: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var fileTranscription: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
