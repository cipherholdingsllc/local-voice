import Foundation

/// Explicit spoken teaching. This is the safe way Local Voice learns.
///
/// Auto-promotion of random STT tokens is what turned "in the" into
/// "Kun Chen". Teaching only fires on phrases Nate actually said, and
/// still refuses common-English sources.
public enum DictationTeacher {
    public struct Lesson: Equatable {
        public var from: String
        public var to: String
        public var kind: Kind

        public enum Kind: Equatable {
            case replacement
            case term
        }
    }

    public struct ParseResult: Equatable {
        public var remainder: String
        public var lessons: [Lesson]
    }

    public struct Result: Equatable {
        public var text: String
        public var message: String?

        public var learned: Bool { message != nil }
    }

    /// Parse teach phrases without writing the dictionary.
    public static func parse(_ text: String) -> ParseResult {
        guard !text.isEmpty else { return ParseResult(remainder: text, lessons: []) }
        var remainder = text
        var lessons: [Lesson] = []

        func strip(_ match: NSTextCheckingResult, in haystack: String) {
            if let whole = Range(match.range(at: 0), in: haystack) {
                remainder.replaceSubrange(whole, with: " ")
            }
        }

        let remember = try? NSRegularExpression(
            pattern: #"(?i)\b(?:remember|learn) that\s+(.+?)\s+(?:is|as|means)\s+(.+?)(?:[.!?]|$)"#
        )
        if let remember {
            let matches = remember.matches(
                in: remainder,
                range: NSRange(remainder.startIndex..., in: remainder)
            )
            for match in matches.reversed() {
                guard match.numberOfRanges >= 3,
                      let fromRange = Range(match.range(at: 1), in: remainder),
                      let toRange = Range(match.range(at: 2), in: remainder)
                else { continue }
                lessons.insert(
                    Lesson(
                        from: String(remainder[fromRange]),
                        to: String(remainder[toRange]),
                        kind: .replacement
                    ),
                    at: 0
                )
                strip(match, in: remainder)
            }
        }

        let addAs = try? NSRegularExpression(
            pattern: #"(?i)\badd\s+(.+?)\s+as\s+(.+?)(?:[.!?]|$)"#
        )
        if let addAs {
            let matches = addAs.matches(
                in: remainder,
                range: NSRange(remainder.startIndex..., in: remainder)
            )
            for match in matches.reversed() {
                guard match.numberOfRanges >= 3,
                      let fromRange = Range(match.range(at: 1), in: remainder),
                      let toRange = Range(match.range(at: 2), in: remainder)
                else { continue }
                lessons.insert(
                    Lesson(
                        from: String(remainder[fromRange]),
                        to: String(remainder[toRange]),
                        kind: .replacement
                    ),
                    at: 0
                )
                strip(match, in: remainder)
            }
        }

        let addTerm = try? NSRegularExpression(
            pattern: #"(?i)\badd\s+(.+?)\s+to(?: the)? dictionary(?:[.!?]|$)"#
        )
        if let addTerm {
            let matches = addTerm.matches(
                in: remainder,
                range: NSRange(remainder.startIndex..., in: remainder)
            )
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let termRange = Range(match.range(at: 1), in: remainder)
                else { continue }
                let term = String(remainder[termRange])
                lessons.insert(
                    Lesson(from: term, to: term, kind: .term),
                    at: 0
                )
                strip(match, in: remainder)
            }
        }

        remainder = remainder
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParseResult(remainder: remainder, lessons: lessons)
    }

    public static func consume(
        _ text: String,
        learner: VocabularyLearner = .shared
    ) -> Result {
        let parsed = parse(text)
        var notices: [String] = []
        for lesson in parsed.lessons {
            switch lesson.kind {
            case .replacement:
                if learner.addReplacement(from: lesson.from, to: lesson.to) {
                    notices.append("Learned \(lesson.from) -> \(lesson.to)")
                }
            case .term:
                if learner.addTerm(lesson.to) {
                    notices.append("Added \(lesson.to) to dictionary")
                }
            }
        }
        let message = notices.isEmpty ? nil : notices.joined(separator: " | ")
        return Result(text: parsed.remainder, message: message)
    }

    /// Field-edit learning: only the changed span, never common English.
    public static func proposedReplacement(
        inserted: String,
        edited: String
    ) -> (from: String, to: String)? {
        let from = inserted.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, from.caseInsensitiveCompare(to) != .orderedSame else {
            return nil
        }
        let fromLower = from.lowercased()
        let toLower = to.lowercased()
        if toLower.hasPrefix(fromLower) { return nil }
        if fromLower.hasPrefix(toLower) { return nil }

        let fromWords = from.split(whereSeparator: \.isWhitespace).map(String.init)
        let toWords = to.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let span = differingSpan(from: fromWords, to: toWords) else { return nil }
        let sourceWords = span.from.split(whereSeparator: \.isWhitespace)
        let targetWords = span.to.split(whereSeparator: \.isWhitespace)
        guard (1...6).contains(sourceWords.count), (1...6).contains(targetWords.count) else {
            return nil
        }
        guard VocabularyLearner.isValidReplacementSource(span.from),
              VocabularyLearner.isValidManualTerm(span.to) else {
            return nil
        }
        if sourceWords.count == 1, !span.to.contains(where: \.isUppercase) {
            return nil
        }
        return (span.from, span.to)
    }

    static func differingSpan(
        from: [String],
        to: [String]
    ) -> (from: String, to: String)? {
        var prefix = 0
        while prefix < min(from.count, to.count),
              from[prefix].caseInsensitiveCompare(to[prefix]) == .orderedSame {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(from.count - prefix, to.count - prefix),
              from[from.count - 1 - suffix].caseInsensitiveCompare(to[to.count - 1 - suffix]) == .orderedSame {
            suffix += 1
        }
        let fromMid = from[prefix..<(from.count - suffix)]
        let toMid = to[prefix..<(to.count - suffix)]
        guard !fromMid.isEmpty, !toMid.isEmpty else { return nil }
        return (fromMid.joined(separator: " "), toMid.joined(separator: " "))
    }
}
