import AppKit
import AVFoundation
import Foundation

public enum LocalVoiceRunState: String, Codable, Sendable {
    case preparing
    case ready
    case listening
    case transcribing
    case refining
    case error

    public var label: String {
        switch self {
        case .preparing: return "Preparing"
        case .ready: return "Ready"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .refining: return "Refining"
        case .error: return "Needs attention"
        }
    }
}

public struct LocalVoiceRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let rawText: String
    public let polishedText: String
    public let applicationName: String
    public let bundleIdentifier: String?
    public let modeName: String
    public let engineName: String
    public let language: String
    public let recordingMilliseconds: Double
    public let finishMilliseconds: Double
    public let contractPair: VoiceContractPair?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawText: String,
        polishedText: String,
        applicationName: String,
        bundleIdentifier: String?,
        modeName: String,
        engineName: String,
        language: String,
        recordingMilliseconds: Double,
        finishMilliseconds: Double,
        contractPair: VoiceContractPair? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.polishedText = polishedText
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.modeName = modeName
        self.engineName = engineName
        self.language = language
        self.recordingMilliseconds = recordingMilliseconds
        self.finishMilliseconds = finishMilliseconds
        self.contractPair = contractPair
    }

    public var text: String {
        polishedText.isEmpty ? rawText : polishedText
    }

    public var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    public var contractJSON: String? {
        guard let contractPair else { return nil }
        return try? contractPair.jsonString()
    }
}

public struct LocalVoiceRuntimeSnapshot: Equatable, Sendable {
    public var state: LocalVoiceRunState
    public var engineName: String
    public var modelName: String
    public var languageName: String
    public var statusDetail: String
    public var privacyVerified: Bool
    public var whisperReady: Bool
    public var accessibilityReady: Bool
    public var microphoneReady: Bool
    public var inputMonitoringReady: Bool
    public var hotkeyReady: Bool
    public var permissionRepairDetail: String? = nil
    public var parakeetReady: Bool = false
    public var parakeetHealthy: Bool = false
    public var lastTakeDetail: String? = nil
    public var lastTakeLandedInField: Bool = false

    public mutating func applyPermissionReadiness(
        _ snapshot: LocalVoicePermissionSnapshot,
        hotkeyMonitorReady: Bool,
        hotkeySummary: String
    ) {
        accessibilityReady = snapshot.accessibility
        microphoneReady = snapshot.microphone
        inputMonitoringReady = snapshot.inputMonitoring
        hotkeyReady = hotkeyMonitorReady
        if state == .listening || state == .transcribing || state == .refining {
            return
        }
        if snapshot.runtimeReady(hotkeyMonitorReady: hotkeyMonitorReady) {
            if state == .error || state == .preparing {
                state = .ready
            }
            statusDetail = "Hold \(hotkeySummary) to dictate"
            permissionRepairDetail = nil
        } else {
            state = .error
            statusDetail = snapshot.blockingSummary
                ?? "The \(hotkeySummary) shortcut monitor could not start"
        }
    }

    public static let preparing = LocalVoiceRuntimeSnapshot(
        state: .preparing,
        engineName: "Detecting engine",
        modelName: Config.load().modelSize,
        languageName: "English",
        statusDetail: "Checking your local voice stack",
        privacyVerified: false,
        whisperReady: Transcriber.findWhisperBinary() != nil,
        accessibilityReady: AXIsProcessTrusted(),
        microphoneReady: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
        inputMonitoringReady: CGPreflightListenEventAccess(),
        hotkeyReady: false
    )
}

public final class LocalVoiceStore: ObservableObject {
    public static let shared = LocalVoiceStore()

    @Published public private(set) var records: [LocalVoiceRecord]
    @Published public private(set) var runtime: LocalVoiceRuntimeSnapshot
    @Published public private(set) var lastError: String?

    private let storageURL: URL?
    private let calendar: Calendar
    private let maximumRecords: Int
    private let retentionDays: Int
    private var persistenceEnabled: Bool

    public init(
        storageURL: URL? = Config.configDir.appendingPathComponent("history.json"),
        records: [LocalVoiceRecord]? = nil,
        runtime: LocalVoiceRuntimeSnapshot = .preparing,
        calendar: Calendar = .current,
        maximumRecords: Int = 1_000,
        retentionDays: Int? = nil,
        persistenceEnabled: Bool? = nil
    ) {
        self.storageURL = storageURL
        self.calendar = calendar
        self.maximumRecords = maximumRecords
        self.retentionDays = max(
            1,
            min(retentionDays ?? Config.load().historyRetentionDays ?? 30, 365)
        )
        self.persistenceEnabled = persistenceEnabled
            ?? (Config.load().saveTranscriptHistory?.value ?? true)
        self.runtime = runtime
        self.lastError = nil

        if let records {
            self.records = records.sorted { $0.createdAt > $1.createdAt }
        } else if let storageURL,
                  let data = try? Data(contentsOf: storageURL),
                  let decoded = try? JSONDecoder.localVoice.decode([LocalVoiceRecord].self, from: data) {
            self.records = decoded.sorted { $0.createdAt > $1.createdAt }
        } else {
            self.records = []
        }
        pruneExpiredRecords()
    }

    public var todayRecords: [LocalVoiceRecord] {
        records.filter { calendar.isDateInToday($0.createdAt) }
    }

    public var todayWordCount: Int {
        todayRecords.reduce(0) { $0 + $1.wordCount }
    }

    public var todayVoiceMinutes: Double {
        todayRecords.reduce(0) { $0 + $1.recordingMilliseconds } / 60_000
    }

    public var medianFinishMilliseconds: Double? {
        let values = records
            .map(\.finishMilliseconds)
            .filter { $0 > 0 }
            .sorted()
        guard !values.isEmpty else { return nil }
        let midpoint = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[midpoint - 1] + values[midpoint]) / 2
        }
        return values[midpoint]
    }

    public func updateRuntime(_ transform: @escaping (inout LocalVoiceRuntimeSnapshot) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateRuntime(transform)
            }
            return
        }
        transform(&runtime)
    }

    public func setState(_ state: LocalVoiceRunState, detail: String) {
        updateRuntime {
            $0.state = state
            $0.statusDetail = detail
        }
    }

    public func setError(_ message: String?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.setError(message) }
            return
        }
        lastError = message
        if let message {
            runtime.state = .error
            runtime.statusDetail = message
        }
    }

    public func append(_ record: LocalVoiceRecord) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.append(record) }
            return
        }
        records.insert(record, at: 0)
        if records.count > maximumRecords {
            records.removeLast(records.count - maximumRecords)
        }
        persist()
    }

    public func replaceRecordsForTesting(_ records: [LocalVoiceRecord]) {
        self.records = records.sorted { $0.createdAt > $1.createdAt }
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

    private func pruneExpiredRecords() {
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        records.removeAll { $0.createdAt < cutoff }
    }

    private func persist() {
        guard persistenceEnabled else { return }
        guard let storageURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.localVoice.encode(records)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            lastError = "History could not be saved: \(error.localizedDescription)"
        }
    }

    public static func preview() -> LocalVoiceStore {
        let now = Date()
        let sampleContract = try? LocalVoiceContract.samplePair()
        let sampleRecords = [
            LocalVoiceRecord(
                createdAt: now.addingTimeInterval(-8 * 60),
                rawText: "Send Dylan the updated technical brief and ask him to check the API contract.",
                polishedText: "Send Dylan the updated technical brief and ask him to check the API contract.",
                applicationName: "Slack",
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                modeName: "Quick message",
                engineName: "Parakeet TDT v3",
                language: "English",
                recordingMilliseconds: 5_800,
                finishMilliseconds: 438,
                contractPair: sampleContract
            ),
            LocalVoiceRecord(
                createdAt: now.addingTimeInterval(-42 * 60),
                rawText: "The sidecar should stay loopback only use a random port and reject untrusted origins.",
                polishedText: "The sidecar should stay loopback-only, use a random port, and reject untrusted origins.",
                applicationName: "Codex",
                bundleIdentifier: "com.openai.codex",
                modeName: "Technical",
                engineName: "Whisper large-v3-turbo",
                language: "English",
                recordingMilliseconds: 7_200,
                finishMilliseconds: 671
            ),
            LocalVoiceRecord(
                createdAt: now.addingTimeInterval(-2 * 60 * 60),
                rawText: "Draft a concise follow up for tomorrow morning.",
                polishedText: "Draft a concise follow-up for tomorrow morning.",
                applicationName: "Mail",
                bundleIdentifier: "com.apple.mail",
                modeName: "Professional",
                engineName: "Parakeet TDT v3",
                language: "English",
                recordingMilliseconds: 3_900,
                finishMilliseconds: 402
            ),
        ]
        let snapshot = LocalVoiceRuntimeSnapshot(
            state: .ready,
            engineName: "Parakeet TDT v3",
            modelName: "large-v3-turbo-q5_0",
            languageName: "English",
            statusDetail: "Hold fn to dictate anywhere",
            privacyVerified: true,
            whisperReady: true,
            accessibilityReady: true,
            microphoneReady: true,
            inputMonitoringReady: true,
            hotkeyReady: true,
            parakeetReady: true,
            parakeetHealthy: true
        )
        return LocalVoiceStore(
            storageURL: nil,
            records: sampleRecords,
            runtime: snapshot,
            retentionDays: 30
        )
    }
}

private extension JSONEncoder {
    static var localVoice: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var localVoice: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
