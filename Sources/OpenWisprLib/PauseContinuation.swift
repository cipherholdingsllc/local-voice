import Foundation

/// Mid-sentence pauses are not sentence ends.
///
/// Streaming STT often inserts a period or a capital after a few seconds of
/// silence, or glues the next word on (`itThere`). Repair those joins with
/// comma, ellipsis, or an en-dash. Never an em-dash.
///
/// Invariants:
/// - Real `?` / `!` sentence ends are left alone.
/// - Isolated `.` after an incomplete tail may become a join mark.
/// - Dots that belong to `...` or U+2026 are never treated as terminators.
/// - Bare preposition + determiner (`to The White House`, `inThe`) is a noun
///   phrase, not a pause join.
/// - Output never contains U+2014.
public enum PauseContinuation {
    public static let enDash = "\u{2013}"
    public static let emDash = "\u{2014}"
    public static let unicodeEllipsis = "\u{2026}"

    private static let continuationStarters: [String] = [
        "Meanwhile", "Although", "Because", "However", "Actually",
        "Anyway", "There", "Then", "This", "That", "These", "Those",
        "They", "Also", "Still", "Plus", "Yet", "The", "And",
        "When", "While", "We", "You", "He", "She", "So", "But",
        "If", "A", "An",
    ]

    private static let glueLeftTokens: Set<String> = [
        "it", "that", "this", "mean", "know", "so", "but", "and",
        "about", "think", "if", "or", "to", "for", "with", "from",
        "in", "on", "at", "of", "as", "like", "when", "because",
    ]

    private static let functionEndings: Set<String> = [
        "and", "or", "but", "so", "because", "if", "when", "while",
        "although", "that", "than", "as", "like", "about", "of", "to",
        "for", "with", "from", "in", "on", "at", "by", "into", "onto",
        "mean", "know",
    ]

    private static let aboutThinkSay: Set<String> = [
        "about", "think", "say", "said", "mean", "know", "put",
    ]

    private static let determiners: Set<String> = ["the", "a", "an"]

    private static let gluedContinuationRegex: NSRegularExpression? = {
        let starters = continuationStarters
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        return try? NSRegularExpression(pattern: "([A-Za-z0-9]+)(\(starters))\\b")
    }()

    private static let falsePeriodRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"([^.!?\n]+?)(\.)\s+([A-Z][A-Za-z]*)\b"#)
    }()

    private static let midSentenceCapitalRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\s+([A-Z][a-z]+)\b"#)
    }()

    public static func repair(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = sanitizeInsertedText(text)
        result = splitGluedContinuations(result)
        result = joinFalseSentenceBreaks(result)
        result = joinMidSentenceCapitals(result)
        return sanitizeInsertedText(result)
    }

    public static func joinMark(left: String) -> String {
        let tail = lastWords(left, 4)
        if isTrailingOff(tail) { return "... " }
        if isContrast(tail) { return " \(enDash) " }
        return ", "
    }

    /// Last-mile lint for anything that can reach the insert path, including
    /// optional Ollama rewrite. Converts em-dash and unicode ellipsis; never
    /// emits U+2014.
    public static func sanitizeInsertedText(_ text: String) -> String {
        var result = text.replacingOccurrences(of: emDash, with: enDash)
        result = result.replacingOccurrences(of: unicodeEllipsis, with: "...")
        result = result.replacingOccurrences(
            of: #"(?<=\S)[ \t]+---+[ \t]+(?=\S)"#,
            with: " \(enDash) ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<=\S)[ \t]+--[ \t]+(?=\S)"#,
            with: " \(enDash) ",
            options: .regularExpression
        )
        result = normalizeEnDashSpacing(result)
        assertNoEmDash(result)
        return result
    }

    static func normalizeEnDashSpacing(_ text: String) -> String {
        let pattern = "\\s*\(NSRegularExpression.escapedPattern(for: enDash))\\s*"
        return text.replacingOccurrences(
            of: pattern,
            with: " \(enDash) ",
            options: .regularExpression
        )
        .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
    }

    /// CamelCase STT glue (`itThere`). Nil for product names (`iPhone`, `CipherLab`).
    static func splitCamelGlue(_ token: String) -> (String, String)? {
        let chars = Array(token)
        guard chars.count >= 3 else { return nil }
        for i in 1..<chars.count {
            let prev = chars[i - 1]
            let cur = chars[i]
            guard prev.isLetter, prev.isLowercase, cur.isLetter, cur.isUppercase else {
                continue
            }
            let left = String(chars[0..<i])
            let right = String(chars[i...])
            guard glueLeftTokens.contains(left.lowercased()) else { return nil }
            guard isContinuationStarter(right) else { return nil }
            return (left, right)
        }
        return nil
    }

    private static func splitGluedContinuations(_ text: String) -> String {
        guard let regex = gluedContinuationRegex else { return text }
        var result = text
        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges == 3,
                  let leftRange = Range(match.range(at: 1), in: result),
                  let rightRange = Range(match.range(at: 2), in: result)
            else { continue }
            let leftToken = String(result[leftRange])
            let starter = String(result[rightRange])
            guard glueLeftTokens.contains(leftToken.lowercased()) else { continue }
            guard isContinuationStarter(starter) else { continue }
            let prefix = String(result[..<leftRange.lowerBound])
            let left = prefix + leftToken
            let mark = clauseJoinMark(left: left, starter: starter) ?? " "
            result.replaceSubrange(
                leftRange.lowerBound..<rightRange.upperBound,
                with: leftToken + mark + starter.lowercased()
            )
        }
        return result
    }

    private static func joinFalseSentenceBreaks(_ text: String) -> String {
        guard let regex = falsePeriodRegex else { return text }
        var result = text
        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let leftRange = Range(match.range(at: 1), in: result),
                  let punctRange = Range(match.range(at: 2), in: result),
                  let wordRange = Range(match.range(at: 3), in: result),
                  let fullRange = Range(match.range, in: result)
            else { continue }
            if isEllipsisDot(in: result, at: punctRange) { continue }
            let left = String(result[leftRange])
            let word = String(result[wordRange])
            guard isContinuationStarter(word) else { continue }
            let trimmed = left.trimmingCharacters(in: .whitespaces)
            if let mark = clauseJoinMark(left: left, starter: word) {
                result.replaceSubrange(
                    fullRange,
                    with: trimmed + mark + word.lowercased()
                )
                continue
            }
            if isDeterminer(word), isPrepositionalTail(left) {
                result.replaceSubrange(fullRange, with: trimmed + " " + word)
            }
        }
        return result
    }

    private static func joinMidSentenceCapitals(_ text: String) -> String {
        guard let regex = midSentenceCapitalRegex else { return text }
        var result = text
        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let wordRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result)
            else { continue }
            let word = String(result[wordRange])
            guard isContinuationStarter(word) else { continue }
            let prefix = String(result[..<fullRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.hasSuffix("?") || prefix.hasSuffix("!") { continue }
            if prefix.hasSuffix("...")
                || prefix.hasSuffix(",")
                || prefix.hasSuffix(enDash) {
                if clauseJoinMark(left: prefix, starter: word) != nil {
                    result.replaceSubrange(wordRange, with: word.lowercased())
                }
                continue
            }
            if let mark = clauseJoinMark(left: prefix, starter: word) {
                result.replaceSubrange(fullRange, with: mark + word.lowercased())
            }
        }
        return result
    }

    /// Join mark when this is a pause continuation. Nil means do not rewrite
    /// the break (complete sentence, or a determiner starting a noun phrase).
    private static func clauseJoinMark(left: String, starter: String) -> String? {
        guard isContinuationStarter(starter) else { return nil }
        let words = lastWords(left, 4)
        if isDeterminer(starter) {
            if isTrailingOff(words) || isContrast(words) {
                return joinMark(left: left)
            }
            return nil
        }
        guard isIncomplete(left) else { return nil }
        return joinMark(left: left)
    }

    private static func isEllipsisDot(in text: String, at range: Range<String.Index>) -> Bool {
        if range.lowerBound > text.startIndex {
            let prev = text[text.index(before: range.lowerBound)]
            if prev == "." { return true }
        }
        if range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            if next == "." { return true }
        }
        return false
    }

    private static func isContinuationStarter(_ word: String) -> Bool {
        continuationStarters.contains { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    private static func isDeterminer(_ word: String) -> Bool {
        determiners.contains(word.lowercased())
    }

    private static func isPrepositionalTail(_ left: String) -> Bool {
        guard let last = lastWords(left, 1).last else { return false }
        return functionEndings.contains(last)
    }

    private static func isIncomplete(_ left: String) -> Bool {
        let words = lastWords(left, 4)
        if isTrailingOff(words) { return true }
        if isContrast(words) { return true }
        guard let last = words.last else { return false }
        if last == "it", words.dropLast().last.map(aboutThinkSay.contains) == true {
            return true
        }
        return functionEndings.contains(last)
    }

    private static func isTrailingOff(_ words: [String]) -> Bool {
        let joined = words.joined(separator: " ")
        if joined.hasSuffix("i mean") || joined.hasSuffix("you know") { return true }
        if joined.hasSuffix("kind of") || joined.hasSuffix("sort of") { return true }
        if joined.hasSuffix("think about it") || joined.hasSuffix("about it") { return true }
        if words.last == "it", words.dropLast().last.map(aboutThinkSay.contains) == true {
            return true
        }
        return false
    }

    private static func isContrast(_ words: [String]) -> Bool {
        let joined = words.joined(separator: " ")
        if joined.contains("rather") || joined.hasSuffix("instead") { return true }
        if words.contains("not"), words.last != "not" { return false }
        return words.last == "not"
    }

    private static func lastWords(_ text: String, _ count: Int) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .suffix(count)
            .map { String($0) }
    }

    private static func assertNoEmDash(_ text: String) {
        #if DEBUG
        assert(!text.contains(emDash), "PauseContinuation must never emit U+2014")
        #endif
        _ = text
    }
}
