import AppKit
import Foundation

public enum ArtifactType: String, Codable, CaseIterable, Sendable, Identifiable {
    case prompt
    case note
    case task

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .prompt: return "Prompt"
        case .note: return "Note"
        case .task: return "Task"
        }
    }

    public var symbol: String {
        switch self {
        case .prompt: return "text.bubble"
        case .note: return "doc.text"
        case .task: return "checklist"
        }
    }
}

public struct LocalVoiceArtifact: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceTranscriptId: UUID
    public let type: ArtifactType
    public var content: String
    public let generatedAt: Date
    public var approvedAt: Date?
    public var exportedAt: Date?
    public var exportCount: Int

    public init(
        id: UUID = UUID(),
        sourceTranscriptId: UUID,
        type: ArtifactType,
        content: String,
        generatedAt: Date = Date(),
        approvedAt: Date? = nil,
        exportedAt: Date? = nil,
        exportCount: Int = 0
    ) {
        self.id = id
        self.sourceTranscriptId = sourceTranscriptId
        self.type = type
        self.content = content
        self.generatedAt = generatedAt
        self.approvedAt = approvedAt
        self.exportedAt = exportedAt
        self.exportCount = exportCount
    }
}

public final class ArtifactStore: ObservableObject {
    public static let shared = ArtifactStore()

    @Published public private(set) var artifacts: [LocalVoiceArtifact]

    private let storageURL: URL
    private let provenanceURL: URL
    private let exportDir: URL

    public init(
        storageURL: URL = Config.configDir.appendingPathComponent("artifacts.json"),
        provenanceURL: URL = Config.configDir.appendingPathComponent("artifacts-provenance.jsonl"),
        exportDir: URL = Config.configDir.appendingPathComponent("Artifacts")
    ) {
        self.storageURL = storageURL
        self.provenanceURL = provenanceURL
        self.exportDir = exportDir

        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder.localVoice.decode([LocalVoiceArtifact].self, from: data) {
            self.artifacts = decoded.sorted { $0.generatedAt > $1.generatedAt }
        } else {
            self.artifacts = []
        }
    }

    public func save(_ artifact: LocalVoiceArtifact) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.save(artifact) }
            return
        }
        if let index = artifacts.firstIndex(where: { $0.id == artifact.id }) {
            artifacts[index] = artifact
        } else {
            artifacts.insert(artifact, at: 0)
        }
        persist()
    }

    public func approve(_ artifact: LocalVoiceArtifact) {
        var updated = artifact
        updated.approvedAt = Date()
        save(updated)
    }

    @discardableResult
    public func export(_ artifact: LocalVoiceArtifact) -> URL? {
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        var updated = artifact
        updated.exportedAt = Date()
        updated.exportCount += 1

        let generatedAt = ISO8601DateFormatter().string(from: artifact.generatedAt)
        let exportedAt = ISO8601DateFormatter().string(from: updated.exportedAt!)
        let header = """
        ---
        source: local-voice://record/\(artifact.sourceTranscriptId.uuidString)
        transcriptId: \(artifact.sourceTranscriptId.uuidString)
        artifactId: \(artifact.id.uuidString)
        artifactType: \(artifact.type.rawValue)
        generatedAt: \(generatedAt)
        exportedAt: \(exportedAt)
        ---

        """
        let markdown = header + artifact.content

        let fileURL = exportDir.appendingPathComponent("\(artifact.id.uuidString).md")
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)

        save(updated)
        appendProvenance(artifactId: artifact.id, at: updated.exportedAt!)
        return fileURL
    }

    public func delete(_ artifact: LocalVoiceArtifact) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.delete(artifact) }
            return
        }
        artifacts.removeAll { $0.id == artifact.id }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.localVoice.encode(artifacts)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            fputs("Artifact store could not persist: \(error.localizedDescription)\n", stderr)
        }
    }

    private func appendProvenance(artifactId: UUID, at: Date) {
        let line: [String: Any] = [
            "artifactId": artifactId.uuidString,
            "action": "export",
            "at": ISO8601DateFormatter().string(from: at),
            "format": "markdown",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: line),
              let string = String(data: data, encoding: .utf8) else { return }
        do {
            try FileManager.default.createDirectory(at: provenanceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let handle = try FileHandle(forWritingTo: provenanceURL)
            _ = handle.seekToEndOfFile()
            handle.write((string + "\n").data(using: .utf8)!)
            handle.closeFile()
        } catch {
            if (try? string.write(to: provenanceURL, atomically: true, encoding: .utf8)) == nil {
                let data = (string + "\n").data(using: .utf8)!
                FileManager.default.createFile(atPath: provenanceURL.path, contents: data, attributes: nil)
            }
        }
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
