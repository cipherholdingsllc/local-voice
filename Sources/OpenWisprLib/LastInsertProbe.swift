import Foundation

public struct LocalVoiceLastInsertProbe: Codable, Equatable, Sendable {
    public static let schemaVersion = "local-voice-last-insert.v2"

    public let schemaVersion: String
    public let capturedAt: Date
    public let outcome: String
    public let accessibilityTrusted: Bool
    public let postEventTrusted: Bool
    public let targetBundle: String?
    public let text: String

    public init(
        capturedAt: Date = Date(),
        outcome: TextInsertOutcome,
        accessibilityTrusted: Bool,
        postEventTrusted: Bool,
        targetBundle: String?,
        text: String
    ) {
        self.schemaVersion = Self.schemaVersion
        self.capturedAt = capturedAt
        self.outcome = String(describing: outcome)
        self.accessibilityTrusted = accessibilityTrusted
        self.postEventTrusted = postEventTrusted
        self.targetBundle = targetBundle
        self.text = String(text.prefix(500))
    }

    public static var fileURL: URL {
        Config.configDir.appendingPathComponent("last-insert.json")
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
