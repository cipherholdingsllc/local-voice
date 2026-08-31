import Foundation

/// Deterministic cleanup after STT + dictionary.
///
/// Strips spoken fillers and applies explicit self-corrections. It does not
/// paraphrase, summarize, or invent words. That path is what previously
/// turned "in the" into "Kun Chen".
public struct DictationCohesion {
    /// Labels the HUD can show after a take. These fire only when the
    /// matching cleanup step actually changed the text. No paraphrase.
    public struct CleanupLabels: Equatable, Sendable {
        public var filler: Bool
        public var correction: Bool
        public var repetition: Bool

        public static let none = CleanupLabels(
            filler: false,
            correction: false,
            repetition: false
        )

        public var isEmpty: Bool {
            !filler && !correction && !repetition
        }

        /// Short Wispr-style tags for the pill detail slot.
        public var pillDetail: String? {
            var parts: [String] = []
            if filler { parts.append("Filler") }
            if correction { parts.append("Correction") }
            if repetition { parts.append("Repeat") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    public static func polish(_ text: String) -> String {
        apply(text).text
    }

    public static func apply(_ text: String) -> (text: String, labels: CleanupLabels) {
        guard !text.isEmpty else { return (text, .none) }
        var labels = CleanupLabels.none
        var result = text

        let afterHyphens = joinSpokenHyphens(result)
        result = afterHyphens

        let afterRetract = retractCorrectedValues(result)
        let afterLastIntent = retractLastIntent(afterRetract)
        let afterScratch = applySelfCorrections(afterLastIntent)
        if afterRetract != result
            || afterLastIntent != afterRetract
            || afterScratch != afterLastIntent {
            labels.correction = true
        }
        result = afterScratch

        let afterFillers = stripFillers(result)
        if afterFillers != result {
            labels.filler = true
        }
        result = afterFillers

        let afterRepeats = collapseRepeatedWords(result)
        if afterRepeats != result {
            labels.repetition = true
        }
        result = afterRepeats

        result = formatSpokenLists(result)
        result = collapseWhitespace(result)
        return (result, labels)
    }

    /// "forty thousand dollars wait, I mean forty-five thousand dollars"
    /// drops only the retracted value, not the sentence frame.
    private static func retractCorrectedValues(_ text: String) -> String {
        let valueWord =
            "(?:zero|oh|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|and|dollars?|bucks?|percent|cent|milliseconds?|ms|bb|blinds?)"
        let pattern =
            "(?i)(?:\(valueWord)(?:-\(valueWord))?(?:\\s+\(valueWord)(?:-\(valueWord))?){0,7})\\s*[,.\\p{Pd}]*\\s*\\b(?:wait,?\\s*I mean(?:t)?|no,?\\s*I mean(?:t)?|sorry,?\\s*I mean(?:t)?)\\b\\s*[,.\\p{Pd}]*\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// Last intent: keep the replacement, drop the retracted value.
    /// "meet at 5 actually 6pm" → "meet at 6pm"
    /// "Friday actually Monday" → "Monday"
    /// "Friday the following Monday" → "Monday"
    /// Does not touch "I actually like this".
    private static let intentScalar: String = {
        let day =
            "(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)"
        let numberWord =
            "(?:zero|oh|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)"
        let clock = "(?:\\s*(?:am|pm|o'?clock))?"
        let digits = "(?:\\d{1,4}(?::\\d{2})?\(clock))"
        let spoken = "(?:\(numberWord)\(clock))"
        return "(?:\(digits)|\(spoken)|\(day))"
    }()

    private static func retractLastIntent(_ text: String) -> String {
        var result = text
        let actually =
            "(?i)\\b\(intentScalar)\\b\\s*[,.]{0,3}\\s*(?:\\.{2,}|…)?\\s*\\b(?:or\\s+)?actually\\s+(?=\(intentScalar)\\b)"
        if let regex = try? NSRegularExpression(pattern: actually) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        let following =
            "(?i)\\b\(intentScalar)\\b\\s+the following\\s+(?=\(intentScalar)\\b)"
        if let regex = try? NSRegularExpression(pattern: following) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        return result
    }

    /// "last dash intent" → "last-intent". Leaves "a dash of salt" and
    /// number-number "one dash two" (pause / em dash) alone.
    private static let hyphenJoinBlocklist: Set<String> = [
        "a", "an", "the", "of", "and", "or", "to", "for", "with", "at", "in",
        "on", "by", "from", "as", "if", "so", "but", "not", "no", "yes", "my",
        "me", "we", "you", "it", "is", "be", "do", "did", "one", "two", "three",
        "four", "five", "six", "seven", "eight", "nine", "ten", "zero", "oh",
        "em", "en",
    ]

    private static func joinSpokenHyphens(_ text: String) -> String {
        let pattern =
            #"(?i)\b([A-Za-z][A-Za-z0-9]{1,24})\s+(?:dash|hyphen|[—–-])\s+([A-Za-z][A-Za-z0-9]{1,24})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let leftRange = Range(match.range(at: 1), in: output),
                  let rightRange = Range(match.range(at: 2), in: output),
                  let whole = Range(match.range(at: 0), in: output)
            else { continue }
            let left = String(output[leftRange])
            let right = String(output[rightRange])
            if hyphenJoinBlocklist.contains(left.lowercased())
                || hyphenJoinBlocklist.contains(right.lowercased()) {
                continue
            }
            output.replaceSubrange(whole, with: "\(left)-\(right)")
        }
        return output
    }

    /// "send it to Dylan scratch that send it to Andras" -> "send it to Andras"
    private static func applySelfCorrections(_ text: String) -> String {
        let pattern =
            #"(?i)(?:^|[.!?]\s+|,\s+)?[^.!?]*?\b(?:scratch that|never mind|forget that)\b[,.]?\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func stripFillers(_ text: String) -> String {
        var result = text
        // Discourse "like" / "you know" only when they are comma-wrapped.
        // Leaves "I like this" and "something like that" alone.
        let wrapped: [(String, String)] = [
            (#"(?i),\s*like\s*,"#, ","),
            (#"(?i),\s*you know\s*,"#, ","),
            (#"(?i)^\s*like\s*,\s*"#, ""),
            (#"(?i)^\s*you know\s*,\s*"#, ""),
        ]
        for (pattern, template) in wrapped {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
        }

        let fillers =
            #"(?i)(?<![A-Za-z0-9])(?:u+h+|um+|er+|ah+|hmm+|mhm|uh-huh)(?![A-Za-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: fillers) else {
            return result
        }
        result = regex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )
        result = result
            .replacingOccurrences(of: #"^[,;:\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+,+"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #",{2,}"#, with: ",", options: .regularExpression)
        return result
    }

    /// Spoken lists, only when two or more markers are present.
    /// Leaves "he's my number one guy" alone.
    private static func formatSpokenLists(_ text: String) -> String {
        let ordinals = [
            "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
            "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        ]
        let numberedCount = ordinals.keys.reduce(0) { count, word in
            let pattern = "\\bnumber \(word)\\b"
            let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            return count + (range == nil ? 0 : 1)
        }
        var result = text
        if numberedCount >= 2 {
            for (word, digit) in ordinals.sorted(by: { $0.key.count > $1.key.count }) {
                let pattern = "(?i)\\bnumber \(word)\\b[,:]?"
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "\n\(digit). "
                )
            }
        }
        let bulletPattern = #"(?i)\bbullet\b"#
        if let bulletRegex = try? NSRegularExpression(pattern: bulletPattern) {
            let bullets = bulletRegex.numberOfMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result)
            )
            if bullets >= 2 {
                result = bulletRegex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "\n- "
                )
            }
        }
        return result
    }

    /// Dictation stutters land as "our, our, our GitHub". Keep the first token.
    private static func collapseRepeatedWords(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(\w+)(?:\s*,?\s+\1\b)+"# ,
            options: [.caseInsensitive]
        ) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "$1"
        )
    }

    private static func collapseWhitespace(_ text: String) -> String {
        let result = text
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return recapitalizeSentences(result)
    }

    private static func recapitalizeSentences(_ text: String) -> String {
        var chars = Array(text)
        var capitalizeNext = true
        for i in chars.indices {
            let ch = chars[i]
            if ch.isNewline || ch == "." || ch == "!" || ch == "?" {
                capitalizeNext = true
                continue
            }
            if ch.isWhitespace { continue }
            if capitalizeNext, ch.isLetter {
                chars[i] = Character(String(ch).uppercased())
                capitalizeNext = false
            } else {
                capitalizeNext = false
            }
        }
        return String(chars)
    }
}
