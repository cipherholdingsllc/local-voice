import Foundation

/// Applies dictionary replacements after STT so custom terms survive engines
/// that do not honor Whisper prompts (Parakeet, polluted prompts, etc.).
public struct VocabularyPostProcessor {
    public struct Replacement: Codable, Equatable, Sendable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public static func apply(
        _ text: String,
        replacements: [Replacement],
        boostTerms: [String] = []
    ) -> String {
        var result = text
        let ordered = replacements
            .filter { !$0.from.isEmpty && !$0.to.isEmpty }
            .sorted { $0.from.count > $1.from.count }

        for rule in ordered {
            result = replaceWholePhrase(result, from: rule.from, to: rule.to)
        }

        for term in boostTerms.sorted(by: { $0.count > $1.count }) {
            guard term.count >= 2 else { continue }
            if result.localizedCaseInsensitiveContains(term) { continue }
            if let match = closestToken(in: result, target: term) {
                result = replaceWholePhrase(result, from: match, to: term)
            }
        }
        return result
    }

    private static func replaceWholePhrase(_ text: String, from: String, to: String) -> String {
        guard !from.isEmpty else { return text }
        let escaped = NSRegularExpression.escapedPattern(for: from)
        let pattern = "(?i)(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: to
        )
    }

    private static func closestToken(in text: String, target: String) -> String? {
        let targetLower = target.lowercased()
        let normalizedTarget = targetLower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        let maxDistance = min(3, max(1, normalizedTarget.count / 3))
        var best: (token: String, distance: Int)?

        for token in tokenize(text) {
            let tokenLower = token.lowercased()
            if tokenLower == targetLower { return nil }
            let distance = min(
                levenshtein(tokenLower, targetLower),
                levenshtein(tokenLower, normalizedTarget)
            )
            guard distance > 0, distance <= maxDistance else { continue }
            if let best, distance >= best.distance { continue }
            best = (token, distance)
        }
        return best?.token
    }

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        for (i, lchar) in left.enumerated() {
            var current = [i + 1]
            for (j, rchar) in right.enumerated() {
                let insertions = previous[j + 1] + 1
                let deletions = current[j] + 1
                let substitutions = previous[j] + (lchar == rchar ? 0 : 1)
                current.append(min(insertions, deletions, substitutions))
            }
            previous = current
        }
        return previous[right.count]
    }
}
