import Foundation

public struct LocalVoicePermissionProbe: Codable, Equatable, Sendable {
    public static let schemaVersion = "local-voice-permission-probe.v2"

    public let schemaVersion: String
    public let capturedAt: Date
    public let bundlePath: String
    public let microphone: Bool
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public let postEvent: Bool
    public let hotkeyMonitorReady: Bool
    public let tapAttempted: Bool
    public let tapStarted: Bool

    public init(
        capturedAt: Date = Date(),
        bundlePath: String,
        microphone: Bool,
        accessibility: Bool,
        inputMonitoring: Bool,
        postEvent: Bool,
        hotkeyMonitorReady: Bool,
        tapAttempted: Bool,
        tapStarted: Bool
    ) {
        self.schemaVersion = Self.schemaVersion
        self.capturedAt = capturedAt
        self.bundlePath = bundlePath
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.postEvent = postEvent
        self.hotkeyMonitorReady = hotkeyMonitorReady
        self.tapAttempted = tapAttempted
        self.tapStarted = tapStarted
    }

    public static var fileURL: URL {
        Config.configDir.appendingPathComponent("permission-snapshot.json")
    }

    public static func make(
        snapshot: LocalVoicePermissionSnapshot,
        hotkeyMonitorReady: Bool,
        tapAttempted: Bool,
        tapStarted: Bool,
        bundlePath: String = Bundle.main.bundlePath
    ) -> LocalVoicePermissionProbe {
        LocalVoicePermissionProbe(
            bundlePath: bundlePath,
            microphone: snapshot.microphone,
            accessibility: snapshot.accessibility,
            inputMonitoring: snapshot.inputMonitoring,
            postEvent: snapshot.postEvent,
            hotkeyMonitorReady: hotkeyMonitorReady,
            tapAttempted: tapAttempted,
            tapStarted: tapStarted
        )
    }

    public func write(to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
