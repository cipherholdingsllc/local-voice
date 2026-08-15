import Foundation

/// Applies dictionary replacements after STT so custom terms survive engines
/// that do not honor Whisper prompts (Parakeet, polluted prompts, etc.).
///
/// Two correction paths, matching the "vocabulary word" vs "misspelling
/// correction" split documented by comparable dictation products: explicit
/// `replacements` are exact, guaranteed literal substitutions; `boostTerms`
/// are dictionary words that get a best-effort fuzzy correction pass because
/// there is no known "this is what STT actually says" mapping for them yet.
public struct VocabularyPostProcessor {
    public struct Replacement: Codable, Equatable, Sendable {
        public enum Origin: String, Codable, Sendable {
            case seeded
            case user
        }

        public let from: String
        public let to: String
        public let origin: Origin?

        public init(from: String, to: String, origin: Origin? = nil) {
            self.from = from
            self.to = to
            self.origin = origin
        }
    }

    /// A fuzzy boost correction that actually fired, so callers can promote
    /// it into a permanent, exact `Replacement` (self-reinforcing dictionary,
    /// same idea as "auto-add" learning from real corrections).
    public struct AppliedCorrection: Equatable {
        public let heard: String
        public let term: String
    }

    public static func apply(
        _ text: String,
        replacements: [Replacement],
        boostTerms: [String] = []
    ) -> (text: String, corrections: [AppliedCorrection]) {
        var result = text
        let ordered = replacements
            .filter { !$0.from.isEmpty && !$0.to.isEmpty }
            .sorted { $0.from.count > $1.from.count }

        for rule in ordered {
            result = replaceWholePhrase(result, from: rule.from, to: rule.to)
        }

        var corrections: [AppliedCorrection] = []
        for term in boostTerms.sorted(by: { $0.count > $1.count }) {
            guard term.count >= 2 else { continue }
            if result.localizedCaseInsensitiveContains(term) { continue }
            guard let match = closestSpan(in: result, target: term) else { continue }
            result = replaceWholePhrase(result, from: match, to: term)
            corrections.append(AppliedCorrection(heard: match, term: term))
        }
        return (result, corrections)
    }

    private static func replaceWholePhrase(_ text: String, from: String, to: String) -> String {
        guard !from.isEmpty else { return text }
        let words = from.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return text }
        let escapedWords = words.map(NSRegularExpression.escapedPattern(for:))
        // Tolerate whatever whitespace actually separates the words in the
        // transcript (single space, double space, etc.) rather than only the
        // exact spacing captured when the match was found.
        let joined = escapedWords.joined(separator: "\\s+")
        let pattern = "(?i)(?<![\\p{L}\\p{N}])\(joined)(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: to)
        )
    }

    /// Finds the closest matching span of consecutive words in `text` for a
    /// (possibly multi-word) `target`. Whisper-style STT keeps word
    /// boundaries between spoken words, so a two-word name that gets
    /// misheard almost always comes out as two separate mis-transcribed
    /// tokens (e.g. "Kuhn Chan"), not one glued token, so the matcher has to
    /// compare word-for-word across a same-length window, not just single
    /// tokens, or multi-word dictionary entries can never be corrected.
    private static func closestSpan(in text: String, target: String) -> String? {
        let targetWords = target
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard !targetWords.isEmpty else { return nil }
        let tokens = tokenize(text)
        guard tokens.count >= targetWords.count else { return nil }

        var best: (span: String, distance: Int)?
        for start in 0...(tokens.count - targetWords.count) {
            let window = Array(tokens[start..<(start + targetWords.count)])
            let span = window.joined(separator: " ")
            if VocabularyLearner.isCommonEnglishSpan(span) { continue }
            guard let distance = windowDistance(window, targetWords) else { continue }
            if span.caseInsensitiveCompare(target) == .orderedSame { return nil }
            if let best, distance >= best.distance { continue }
            best = (span, distance)
        }
        if let best { return best.span }

        // Fallback for STT output that glues a multi-word target into one
        // token (e.g. "kunch" for "Kun Chen"): compare single tokens against
        // the target with whitespace stripped.
        if targetWords.count > 1 {
            return closestGluedToken(in: tokens, target: target)
        }
        return nil
    }

    private static func closestGluedToken(in tokens: [String], target: String) -> String? {
        let normalizedTarget = target
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        let maxDistance = min(3, max(1, normalizedTarget.count / 3))
        var best: (token: String, distance: Int)?
        for token in tokens {
            let distance = levenshtein(token.lowercased(), normalizedTarget)
            guard distance > 0, distance <= maxDistance else { continue }
            if let best, distance >= best.distance { continue }
            best = (token, distance)
        }
        return best?.token
    }

    /// Every word in the window must individually resemble the corresponding
    /// target word (bounded per-word distance) so a phrase only corrects
    /// when the whole shape lines up, not just an aggregate character count.
    private static func windowDistance(_ window: [String], _ targetWords: [String]) -> Int? {
        guard window.count == targetWords.count else { return nil }
        var total = 0
        var identical = true
        for (heard, wanted) in zip(window, targetWords) {
            let heardLower = heard.lowercased()
            let wantedLower = wanted.lowercased()
            if heardLower != wantedLower { identical = false }
            let distance = levenshtein(heardLower, wantedLower)
            guard distance <= maxWordDistance(for: wantedLower) else { return nil }
            total += distance
        }
        guard !identical else { return nil }
        return total
    }

    /// Short words need a looser relative bound: real ASR mishears of a
    /// 3-letter name (e.g. "Kun" -> "Coon") routinely differ by more than
    /// one character, so a flat distance-of-1 cap misses almost every real
    /// homophone substitution. Longer words keep a tighter relative bound to
    /// avoid correcting unrelated words that merely happen to be short-edit
    /// away.
    private static func maxWordDistance(for word: String) -> Int {
        switch word.count {
        case 0...2: return 1
        case 3...4: return 2
        case 5...7: return 2
        default: return 3
        }
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
