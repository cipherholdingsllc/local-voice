import Foundation

public enum ConnectCandidateStatus: String, Codable, Sendable {
    case pending
    case approved
    case dismissed
}

public struct CorrectionCandidate: Codable, Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let from: String
    public let to: String
    public var sourceRecordIDs: Set<UUID>
    public let firstObservedAt: Date
    public var lastObservedAt: Date
    public var status: ConnectCandidateStatus
    public var decidedAt: Date?

    public var occurrenceCount: Int { sourceRecordIDs.count }
    public var isVisible: Bool { occurrenceCount >= 2 && status == .pending }
}

public final class ConnectStore: ObservableObject {
    public static let shared = ConnectStore()

    @Published public private(set) var candidates: [CorrectionCandidate]
    @Published public private(set) var clusters: [RelatedThoughtCluster] = []
    @Published public private(set) var lastRebuiltAt: Date?

    private struct Snapshot: Codable {
        let schemaVersion: Int
        var candidates: [CorrectionCandidate]
    }

    private let storageURL: URL
    private let now: () -> Date
    private let retentionDays: Int
    private let persistenceEnabled: Bool

    public init(
        storageURL: URL = Config.configDir.appendingPathComponent("connect-decisions.json"),
        now: @escaping () -> Date = Date.init,
        retentionDays: Int = 30,
        persistenceEnabled: Bool = true
    ) {
        self.storageURL = storageURL
        self.now = now
        self.retentionDays = retentionDays
        self.persistenceEnabled = persistenceEnabled
        if let data = try? Data(contentsOf: storageURL),
           let snapshot = try? JSONDecoder.connect.decode(Snapshot.self, from: data),
           snapshot.schemaVersion == 1 {
            candidates = snapshot.candidates
        } else {
            candidates = []
        }
        prune()
    }

    public var pendingCandidates: [CorrectionCandidate] {
        candidates.filter(\.isVisible).sorted {
            $0.occurrenceCount == $1.occurrenceCount
                ? $0.lastObservedAt > $1.lastObservedAt
                : $0.occurrenceCount > $1.occurrenceCount
        }
    }

    public func observe(from: String, to: String, sourceRecordID: UUID, at: Date? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.observe(from: from, to: to, sourceRecordID: sourceRecordID, at: at)
            }
            return
        }
        let source = normalize(from)
        let target = normalize(to)
        guard !source.isEmpty, !target.isEmpty, source != target else { return }
        let key = source + "\u{001F}" + target
        let observedAt = at ?? now()
        if let index = candidates.firstIndex(where: { $0.key == key }) {
            guard candidates[index].status == .pending else { return }
            candidates[index].sourceRecordIDs.insert(sourceRecordID)
            candidates[index].lastObservedAt = max(candidates[index].lastObservedAt, observedAt)
        } else {
            candidates.append(CorrectionCandidate(
                key: key,
                from: from.trimmingCharacters(in: .whitespacesAndNewlines),
                to: to.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceRecordIDs: [sourceRecordID],
                firstObservedAt: observedAt,
                lastObservedAt: observedAt,
                status: .pending
            ))
        }
        prune()
        persist()
    }

    @discardableResult
    public func approve(_ candidate: CorrectionCandidate, learner: VocabularyLearner = .shared) -> Bool {
        guard learner.addReplacement(from: candidate.from, to: candidate.to) else { return false }
        decide(candidate, status: .approved)
        return true
    }

    public func dismiss(_ candidate: CorrectionCandidate) {
        decide(candidate, status: .dismissed)
    }

    public func rebuild(records: [LocalVoiceRecord]) {
        let result = ConnectIntelligence.clusters(from: records)
        DispatchQueue.main.async { [weak self] in
            self?.clusters = result
            self?.lastRebuiltAt = self?.now()
        }
    }

    public func rebuildAsync(records: [LocalVoiceRecord]) {
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.rebuild(records: records) }
    }

    private func decide(_ candidate: CorrectionCandidate, status: ConnectCandidateStatus) {
        guard let index = candidates.firstIndex(where: { $0.key == candidate.key }) else { return }
        candidates[index].status = status
        candidates[index].decidedAt = now()
        persist()
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-Double(retentionDays) * 86_400)
        candidates.removeAll { $0.status == .pending && $0.lastObservedAt < cutoff }
        if candidates.count > 500 {
            candidates = Array(candidates.sorted { $0.lastObservedAt > $1.lastObservedAt }.prefix(500))
        }
    }

    private func normalize(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func persist() {
        guard persistenceEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.connect.encode(Snapshot(schemaVersion: 1, candidates: candidates))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            fputs("Connect store could not persist: \(error.localizedDescription)\n", stderr)
        }
    }
}

private extension JSONEncoder {
    static var connect: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var connect: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
