import AppKit
import Foundation

public enum ArtifactType: String, Codable, CaseIterable, Sendable, Identifiable {
    case prompt
    case note
    case task
    case decision
    case ideaBrief
    case checklist
    case reusableInstruction
    case skillCandidate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .prompt: return "Prompt"
        case .note: return "Note"
        case .task: return "Task"
        case .decision: return "Decision"
        case .ideaBrief: return "Idea brief"
        case .checklist: return "Checklist"
        case .reusableInstruction: return "Instruction"
        case .skillCandidate: return "Skill candidate"
        }
    }

    public var symbol: String {
        switch self {
        case .prompt: return "text.bubble"
        case .note: return "doc.text"
        case .task: return "checklist"
        case .decision: return "checkmark.seal"
        case .ideaBrief: return "lightbulb"
        case .checklist: return "list.bullet.rectangle"
        case .reusableInstruction: return "repeat"
        case .skillCandidate: return "puzzlepiece"
        }
    }
}

public enum ReuseOutcome: String, Codable, CaseIterable, Sendable, Identifiable {
    case helpful
    case edited
    case rejected

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .helpful: return "Helpful"
        case .edited: return "Edited"
        case .rejected: return "Rejected"
        }
    }

    public var symbol: String {
        switch self {
        case .helpful: return "hand.thumbsup"
        case .edited: return "pencil"
        case .rejected: return "hand.thumbsdown"
        }
    }
}

/// A manual record that an approved artifact was later reused (or not).
/// This is an operator-entered signal, not automatic outcome measurement.
public struct ReuseEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let outcome: ReuseOutcome
    public let note: String?
    public let at: Date

    public init(id: UUID = UUID(), outcome: ReuseOutcome, note: String? = nil, at: Date = Date()) {
        self.id = id
        self.outcome = outcome
        self.note = note
        self.at = at
    }
}

public struct LocalVoiceArtifact: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceTranscriptId: UUID
    public let type: ArtifactType
    /// The current, operator-facing content. Starts as the generated draft and
    /// becomes the approved text after any edits.
    public var content: String
    public let generatedAt: Date
    public var approvedAt: Date?
    public var exportedAt: Date?
    public var exportCount: Int
    /// Which engine produced the draft: "template" or "ollama". Nil for
    /// artifacts saved before this field existed.
    public var engine: String?
    /// The machine-generated draft before operator edits. When it differs from
    /// `content`, the artifact was edited after generation — this is how
    /// inferred text is distinguished from operator-approved text.
    public var generatedContent: String?
    /// Manual reuse outcomes recorded after export. Append-only.
    public var reuseEvents: [ReuseEvent]
    /// Directory slug used when this artifact was installed as a SKILL.md.
    /// Nil until the first skill export.
    public var skillSlug: String?

    public init(
        id: UUID = UUID(),
        sourceTranscriptId: UUID,
        type: ArtifactType,
        content: String,
        generatedAt: Date = Date(),
        approvedAt: Date? = nil,
        exportedAt: Date? = nil,
        exportCount: Int = 0,
        engine: String? = nil,
        generatedContent: String? = nil,
        reuseEvents: [ReuseEvent] = [],
        skillSlug: String? = nil
    ) {
        self.id = id
        self.sourceTranscriptId = sourceTranscriptId
        self.type = type
        self.content = content
        self.generatedAt = generatedAt
        self.approvedAt = approvedAt
        self.exportedAt = exportedAt
        self.exportCount = exportCount
        self.engine = engine
        self.generatedContent = generatedContent
        self.reuseEvents = reuseEvents
        self.skillSlug = skillSlug
    }

    public var isApproved: Bool { approvedAt != nil }

    /// True when the operator changed the machine draft before approving —
    /// i.e. the exported text is no longer purely inferred content.
    public var userEdited: Bool {
        guard let generatedContent else { return false }
        return generatedContent != content
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceTranscriptId, type, content, generatedAt, approvedAt
        case exportedAt, exportCount, engine, generatedContent, reuseEvents
        case skillSlug
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceTranscriptId = try container.decode(UUID.self, forKey: .sourceTranscriptId)
        type = try container.decode(ArtifactType.self, forKey: .type)
        content = try container.decode(String.self, forKey: .content)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        approvedAt = try container.decodeIfPresent(Date.self, forKey: .approvedAt)
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt)
        exportCount = try container.decodeIfPresent(Int.self, forKey: .exportCount) ?? 0
        engine = try container.decodeIfPresent(String.self, forKey: .engine)
        generatedContent = try container.decodeIfPresent(String.self, forKey: .generatedContent)
        reuseEvents = try container.decodeIfPresent([ReuseEvent].self, forKey: .reuseEvents) ?? []
        skillSlug = try container.decodeIfPresent(String.self, forKey: .skillSlug)
    }
}

public final class ArtifactStore: ObservableObject {
    public static let shared = ArtifactStore()

    @Published public private(set) var artifacts: [LocalVoiceArtifact]

    private let storageURL: URL
    private let provenanceURL: URL
    private let exportDir: URL
    /// Canonical store-owned copy of installed skills; cascades on delete.
    private let skillsDir: URL
    /// Where agents actually load skills from (Devin user-level skills).
    private let skillInstallDir: URL

    public init(
        storageURL: URL = Config.configDir.appendingPathComponent("artifacts.json"),
        provenanceURL: URL = Config.configDir.appendingPathComponent("artifacts-provenance.jsonl"),
        exportDir: URL = Config.configDir.appendingPathComponent("Artifacts"),
        skillsDir: URL = Config.configDir.appendingPathComponent("Skills"),
        skillInstallDir: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/devin/skills")
    ) {
        self.storageURL = storageURL
        self.provenanceURL = provenanceURL
        self.exportDir = exportDir
        self.skillsDir = skillsDir
        self.skillInstallDir = skillInstallDir

        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder.localVoice.decode([LocalVoiceArtifact].self, from: data) {
            self.artifacts = decoded.sorted { $0.generatedAt > $1.generatedAt }
        } else {
            self.artifacts = []
        }
    }

    public func artifact(id: UUID) -> LocalVoiceArtifact? {
        artifacts.first { $0.id == id }
    }

    public func artifacts(sourcingFrom recordID: UUID) -> [LocalVoiceArtifact] {
        artifacts.filter { $0.sourceTranscriptId == recordID }
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

    /// Record a manual reuse outcome. Re-reads the stored artifact so a stale
    /// UI copy cannot drop events, and ignores an identical outcome+note tapped
    /// again within 60 seconds (double-tap protection).
    public func recordReuse(_ artifact: LocalVoiceArtifact, outcome: ReuseOutcome, note: String? = nil) {
        var updated = self.artifact(id: artifact.id) ?? artifact
        if let last = updated.reuseEvents.last,
           last.outcome == outcome,
           last.note == note,
           Date().timeIntervalSince(last.at) < 60 {
            return
        }
        updated.reuseEvents.append(ReuseEvent(outcome: outcome, note: note))
        save(updated)
        appendProvenance(artifactId: artifact.id, action: "reuse:\(outcome.rawValue)", at: Date())
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
        generatedBy: \(artifact.engine ?? "unknown")
        approved: \(artifact.isApproved)
        editedAfterGeneration: \(artifact.userEdited)
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
        appendProvenance(artifactId: artifact.id, action: "export", at: updated.exportedAt!)
        return fileURL
    }

    /// Whether this artifact can be installed as an agent skill.
    public static func isSkillExportable(_ artifact: LocalVoiceArtifact) -> Bool {
        artifact.isApproved &&
            (artifact.type == .skillCandidate || artifact.type == .reusableInstruction)
    }

    /// Install an approved skill candidate / reusable instruction as a
    /// SKILL.md agents can load. Writes the canonical copy under the
    /// local-voice config dir (so deletion cascades) and installs a copy into
    /// the Devin user skills directory.
    @discardableResult
    public func exportSkill(_ artifact: LocalVoiceArtifact) -> URL? {
        guard ArtifactStore.isSkillExportable(artifact) else { return nil }

        let slug = artifact.skillSlug ?? resolvedSkillSlug(for: artifact)
        let exportedAt = ISO8601DateFormatter().string(from: Date())
        let description = Self.skillDescription(for: artifact)
        let skillMarkdown = """
        ---
        name: \(slug)
        description: \(description)
        ---

        \(artifact.content)

        <!--
        provenance:
          source: local-voice://record/\(artifact.sourceTranscriptId.uuidString)
          artifactId: \(artifact.id.uuidString)
          artifactType: \(artifact.type.rawValue)
          generatedBy: \(artifact.engine ?? "unknown")
          approved: \(artifact.isApproved)
          editedAfterGeneration: \(artifact.userEdited)
          exportedAt: \(exportedAt)
        -->
        """

        let canonicalDir = skillsDir.appendingPathComponent(slug)
        let installDir = skillInstallDir.appendingPathComponent(slug)
        do {
            for dir in [canonicalDir, installDir] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try skillMarkdown.write(
                    to: dir.appendingPathComponent("SKILL.md"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        } catch {
            return nil
        }

        var updated = artifact
        updated.skillSlug = slug
        save(updated)
        appendProvenance(artifactId: artifact.id, action: "export:skill", at: Date())
        return installDir.appendingPathComponent("SKILL.md")
    }

    /// Derive a stable directory slug from the artifact content: first Markdown
    /// heading when present, else the leading words of the first line.
    static func skillSlugBase(for artifact: LocalVoiceArtifact) -> String {
        let lines = artifact.content.components(separatedBy: .newlines)
        let source = (lines.first { $0.hasPrefix("#") } ?? lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
        let words = source
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
        let slug = words.joined(separator: "-")
        return slug.isEmpty ? "skill-\(artifact.id.uuidString.prefix(8).lowercased())" : String(slug.prefix(40))
    }

    static func skillDescription(for artifact: LocalVoiceArtifact) -> String {
        let line = artifact.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? artifact.type.title
        return String(line.prefix(100))
    }

    /// Unique slug for this artifact: reuses its stored slug, otherwise takes
    /// the content-derived base and suffixes on collision with another
    /// artifact's existing install.
    private func resolvedSkillSlug(for artifact: LocalVoiceArtifact) -> String {
        let base = Self.skillSlugBase(for: artifact)
        let claimed = Set(artifacts.compactMap { $0.id == artifact.id ? nil : $0.skillSlug })
        guard claimed.contains(base) else { return base }
        return "\(base)-\(artifact.id.uuidString.prefix(4).lowercased())"
    }

    public func delete(_ artifact: LocalVoiceArtifact) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.delete(artifact) }
            return
        }
        artifacts.removeAll { $0.id == artifact.id }
        try? FileManager.default.removeItem(
            at: exportDir.appendingPathComponent("\(artifact.id.uuidString).md")
        )
        if let slug = artifact.skillSlug {
            try? FileManager.default.removeItem(at: skillsDir.appendingPathComponent(slug))
            try? FileManager.default.removeItem(at: skillInstallDir.appendingPathComponent(slug))
        }
        persist()
    }

    /// Deletion policy: when a source transcript is deleted, every artifact
    /// derived from it is deleted too (stored record + exported Markdown file
    /// under Artifacts/). The append-only provenance log is a ledger and is
    /// not rewritten.
    public func deleteArtifacts(sourcingFrom recordID: UUID) {
        for artifact in artifacts(sourcingFrom: recordID) {
            delete(artifact)
        }
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

    private func appendProvenance(artifactId: UUID, action: String, at: Date) {
        let line: [String: Any] = [
            "artifactId": artifactId.uuidString,
            "action": action,
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
