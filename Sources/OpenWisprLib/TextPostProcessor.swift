import Foundation

public struct TextPostProcessor {
    private static let replacements: [(pattern: String, replacement: String)] = [
        ("\\bperiod\\b", "."),
        ("\\bfull stop\\b", "."),
        ("\\b[ck]a?r?ma\\b", ","),
        ("\\bcomma\\b", ","),
        ("\\bquestion mark\\b", "?"),
        ("\\bexclamation mark\\b", "!"),
        ("\\bexclamation point\\b", "!"),
        ("\\bcolon\\b", ":"),
        ("\\bsemicolon\\b", ";"),
        ("\\bsemi colon\\b", ";"),
        ("\\bellipsis\\b", "..."),
        ("\\bdash\\b", " —"),
        ("\\bhyphen\\b", "-"),
        ("\\bopen quote\\b", "\""),
        ("\\bclose quote\\b", "\""),
        ("\\bopen paren\\b", "("),
        ("\\bclose paren\\b", ")"),
        ("\\bnew line\\b", "\n"),
        ("\\bnewline\\b", "\n"),
        ("\\bnew paragraph\\b", "\n\n"),
    ]

    public static func process(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
        result = fixSpacingAroundPunctuation(result)
        result = ensureSpaceAfterPunctuation(result)
        return result
    }

    /// Always-on structural commands. Does not rewrite "period" / "comma",
    /// which stay behind the spoken-punctuation setting because they collide
    /// with normal English ("period of time").
    public static func processStructural(_ text: String) -> String {
        let structural: [(String, String)] = [
            ("\\bnew paragraph\\b", "\n\n"),
            ("\\bnew line\\b", "\n"),
            ("\\bnewline\\b", "\n"),
        ]
        var result = text
        for (pattern, replacement) in structural {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
        return result
    }

    private static func fixSpacingAroundPunctuation(_ text: String) -> String {
        var result = text
        guard let regex = try? NSRegularExpression(pattern: "\\s+([.,?!:;])", options: []) else { return result }
        result = regex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1"
        )
        return result
    }

    private static func ensureSpaceAfterPunctuation(_ text: String) -> String {
        var result = text
        guard let regex = try? NSRegularExpression(pattern: "([.,?!:;])(\\w)", options: []) else { return result }
        result = regex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1 $2"
        )
        return result
    }
}
