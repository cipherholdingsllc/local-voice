import Foundation

public struct RelatedThoughtCluster: Identifiable, Equatable, Sendable {
    public let id: String
    public let recordIDs: [UUID]
    public let sharedTerms: [String]
    public let score: Int
    public let earliest: Date
    public let latest: Date

    public var title: String { sharedTerms.first ?? "Related thoughts" }
}

public enum ConnectIntelligence {
    static let minimumScore = 6
    private static let stopWords: Set<String> = [
        "about", "after", "again", "also", "because", "been", "before", "being", "could",
        "does", "from", "have", "into", "just", "like", "make", "more", "should", "some",
        "that", "their", "them", "then", "there", "these", "they", "this", "those", "very",
        "want", "were", "what", "when", "where", "which", "while", "with", "would", "your"
    ]

    public static func clusters(from records: [LocalVoiceRecord]) -> [RelatedThoughtCluster] {
        guard records.count > 1 else { return [] }
        let features = Dictionary(uniqueKeysWithValues: records.map { ($0.id, featureSet($0.text)) })
        var frequencies: [String: Int] = [:]
        for feature in features.values {
            for token in feature.tokens { frequencies[token, default: 0] += 1 }
            for phrase in feature.bigrams.union(feature.trigrams) { frequencies[phrase, default: 0] += 1 }
        }
        let maximumGenericFrequency = max(2, records.count / 4)
        var relationships: [(records: [LocalVoiceRecord], terms: [String], score: Int)] = []

        let inverted = invertedIndex(features: features)
        var candidatePairs = Set<Set<UUID>>()
        for ids in inverted.values where ids.count > 1 && ids.count <= maximumGenericFrequency {
            let sorted = ids.sorted { $0.uuidString < $1.uuidString }
            for i in 0..<sorted.count {
                for j in (i + 1)..<sorted.count { candidatePairs.insert([sorted[i], sorted[j]]) }
            }
        }

        for pair in candidatePairs {
            let ids = Array(pair)
            guard ids.count == 2,
                  let lhs = records.first(where: { $0.id == ids[0] }),
                  let rhs = records.first(where: { $0.id == ids[1] }),
                  let left = features[lhs.id], let right = features[rhs.id] else { continue }
            let sharedTrigrams = left.trigrams.intersection(right.trigrams).filter { frequencies[$0, default: 0] <= maximumGenericFrequency }
            let sharedBigrams = left.bigrams.intersection(right.bigrams).filter { frequencies[$0, default: 0] <= maximumGenericFrequency }
            let sharedTokens = left.tokens.intersection(right.tokens).filter { frequencies[$0, default: 0] <= maximumGenericFrequency }
            guard !sharedBigrams.isEmpty || !sharedTrigrams.isEmpty || sharedTokens.count >= 2 else { continue }
            var score = sharedTrigrams.count * 8 + sharedBigrams.count * 5 + sharedTokens.count * 2
            if lhs.applicationName == rhs.applicationName { score += 1 }
            if lhs.modeName == rhs.modeName { score += 1 }
            if abs(lhs.createdAt.timeIntervalSince(rhs.createdAt)) <= 14 * 86_400 { score += 2 }
            guard score >= minimumScore else { continue }
            let terms = sharedTrigrams.union(sharedBigrams).union(sharedTokens).sorted { lhs, rhs in
                let leftWords = lhs.split(separator: " ").count
                let rightWords = rhs.split(separator: " ").count
                return leftWords == rightWords ? lhs < rhs : leftWords > rightWords
            }
            relationships.append((records: [lhs, rhs], terms: terms, score: score))
        }

        return relationships.map { relationship in
            let members = relationship.records
            let ids = members.map(\.id).sorted { $0.uuidString < $1.uuidString }
            return RelatedThoughtCluster(
                id: ids.map(\.uuidString).joined(separator: ":"),
                recordIDs: ids,
                sharedTerms: Array(relationship.terms.prefix(5)),
                score: relationship.score,
                earliest: members.map(\.createdAt).min()!,
                latest: members.map(\.createdAt).max()!
            )
        }.sorted {
            $0.score == $1.score ? $0.latest > $1.latest : $0.score > $1.score
        }.prefix(50).map { $0 }
    }

    private struct Features {
        let tokens: Set<String>
        let bigrams: Set<String>
        let trigrams: Set<String>
        var all: Set<String> { tokens.union(bigrams).union(trigrams) }
    }

    private static func featureSet(_ text: String) -> Features {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) }
        let bigrams = Set(zip(words, words.dropFirst()).map { "\($0) \($1)" })
        let trigrams = words.count < 3 ? [] : Set((0...(words.count - 3)).map { "\(words[$0]) \(words[$0 + 1]) \(words[$0 + 2])" })
        return Features(tokens: Set(words), bigrams: bigrams, trigrams: trigrams)
    }

    private static func invertedIndex(features: [UUID: Features]) -> [String: Set<UUID>] {
        var result: [String: Set<UUID>] = [:]
        for (id, feature) in features {
            for term in feature.all { result[term, default: []].insert(id) }
        }
        return result
    }
}
