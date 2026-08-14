import Foundation

/// Deterministic cleanup after STT + dictionary.
///
/// Strips spoken fillers and applies explicit self-corrections. It does not
/// paraphrase, summarize, or invent words. That path is what previously
/// turned "in the" into "Kun Chen".
public struct DictationCohesion {
    public static func polish(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = applySelfCorrections(text)
        result = stripFillers(result)
        result = collapseWhitespace(result)
        return result
    }

    /// "send it to Dylan scratch that send it to Andras" ? "send it to Andras"
    private static func applySelfCorrections(_ text: String) -> String {
        let pattern =
            #"(?i)(?:^|[.!?]\s+|,\s+)?[^.!?]*?\b(?:scratch that|never mind|forget that|wait I mean|no I mean)\b[,.]?\s*"#
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
