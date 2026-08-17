import Foundation

/// Deterministic cleanup after STT + dictionary.
///
/// Strips spoken fillers and applies explicit self-corrections. It does not
/// paraphrase, summarize, or invent words. That path is what previously
/// turned "in the" into "Kun Chen".
public struct DictationCohesion {
    public static func polish(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = retractCorrectedValues(text)
        result = applySelfCorrections(result)
        result = stripFillers(result)
        result = collapseRepeatedWords(result)
        result = formatSpokenLists(result)
        result = collapseWhitespace(result)
        result = PauseContinuation.repair(result)
        result = recapitalizeSentences(result)
        return result
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
        return result
    }

    /// Capitalize after a real sentence end. Ellipsis (`...`) is a pause, not
    /// a terminator, so the following word stays lowercase.
    static func recapitalizeSentences(_ text: String) -> String {
        var chars = Array(text)
        var capitalizeNext = true
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "." {
                var count = 0
                var j = i
                while j < chars.count, chars[j] == "." {
                    count += 1
                    j += 1
                }
                capitalizeNext = count < 3
                i = j
                continue
            }
            if ch.isNewline || ch == "!" || ch == "?" {
                capitalizeNext = true
                i += 1
                continue
            }
            if ch.isWhitespace {
                i += 1
                continue
            }
            if capitalizeNext, ch.isLetter {
                chars[i] = Character(String(ch).uppercased())
                capitalizeNext = false
            } else {
                capitalizeNext = false
            }
            i += 1
        }
        return String(chars)
    }
}
