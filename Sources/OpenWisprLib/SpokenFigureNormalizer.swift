import Foundation

/// Spoken amounts and units to written figures.
///
/// Only fires when a number-word span is followed by a unit (dollars,
/// percent, milliseconds, big blinds). Ordinary English counts stay words.
public enum SpokenFigureNormalizer {
    private static let ones: [String: Int] = [
        "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3,
        "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let scales: [String: Int] = [
        "hundred": 100,
        "thousand": 1_000,
        "million": 1_000_000,
        "billion": 1_000_000_000,
    ]

    public static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = rewritePortDigits(text)
        result = rewriteDigitAmounts(result)
        result = rewriteUnitAmounts(result)
        return result
    }

    /// STT sometimes emits "45 thousand dollars" instead of number-words.
    /// Ordinary counts without a unit ("2 ideas") stay untouched.
    private static func rewriteDigitAmounts(_ text: String) -> String {
        let pattern =
            #"(?i)\b(\d{1,7}(?:,\d{3})*)(?:\s+(thousand|million|billion))?\s+(dollars?|bucks?|percent|per\s+cent)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 4,
                  let valueRange = Range(match.range(at: 1), in: output),
                  let unitRange = Range(match.range(at: 3), in: output),
                  let whole = Range(match.range(at: 0), in: output)
            else { continue }
            let raw = String(output[valueRange]).replacingOccurrences(of: ",", with: "")
            guard let base = Int(raw) else { continue }
            var value = base
            if match.range(at: 2).location != NSNotFound,
               let scaleRange = Range(match.range(at: 2), in: output) {
                switch String(output[scaleRange]).lowercased() {
                case "thousand": value = base * 1_000
                case "million": value = base * 1_000_000
                case "billion": value = base * 1_000_000_000
                default: break
                }
            }
            let unit = String(output[unitRange]).lowercased()
            output.replaceSubrange(whole, with: format(value, unit: unit))
        }
        return output
    }

    private static func rewriteUnitAmounts(_ text: String) -> String {
        let words = (Array(ones.keys) + Array(tens.keys) + Array(scales.keys))
            .sorted { $0.count > $1.count }
            .joined(separator: "|")
        let number = "(?:\(words))(?:-(?:\(words)))?"
        let pattern =
            "(?i)\\b((?:\(number)(?:\\s+(?:and|\(number))){0,7}))\\s+(dollars?|bucks?|percent|per\\s+cent|milliseconds?|ms|bb|big\\s+blinds?)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let numberRange = Range(match.range(at: 1), in: output),
                  let unitRange = Range(match.range(at: 2), in: output),
                  let whole = Range(match.range(at: 0), in: output)
            else { continue }
            let numberWords = String(output[numberRange])
            let unit = String(output[unitRange]).lowercased()
            let tokens = tokenizeNumberWords(numberWords)
            guard let value = parseNumberWords(tokens) else { continue }
            output.replaceSubrange(whole, with: format(value, unit: unit))
        }
        return output
    }

    private static func rewritePortDigits(_ text: String) -> String {
        let pattern =
            #"(?i)\bport\s+((?:(?:zero|oh|one|two|three|four|five|six|seven|eight|nine)\s+){2,5}(?:zero|oh|one|two|three|four|five|six|seven|eight|nine))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let spokenRange = Range(match.range(at: 1), in: output),
                  let whole = Range(match.range(at: 0), in: output)
            else { continue }
            let spoken = String(output[spokenRange])
            let digits = tokenizeNumberWords(spoken).compactMap { ones[$0] }.map(String.init)
            guard digits.count >= 3 else { continue }
            output.replaceSubrange(whole, with: "port \(digits.joined())")
        }
        return output
    }

    private static func tokenizeNumberWords(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func parseNumberWords(_ tokens: [String]) -> Int? {
        guard !tokens.isEmpty else { return nil }
        var total = 0
        var current = 0
        var sawValue = false
        for token in tokens {
            if token == "and" { continue }
            if let onesValue = ones[token] {
                current += onesValue
                sawValue = true
                continue
            }
            if let tensValue = tens[token] {
                current += tensValue
                sawValue = true
                continue
            }
            if let scale = scales[token] {
                if scale == 100 {
                    current = max(current, 1) * 100
                } else {
                    total += max(current, 1) * scale
                    current = 0
                }
                sawValue = true
                continue
            }
            return nil
        }
        guard sawValue else { return nil }
        return total + current
    }

    private static func format(_ value: Int, unit: String) -> String {
        if unit.hasPrefix("dollar") || unit.hasPrefix("buck") {
            return "$\(grouped(value))"
        }
        if unit.contains("percent") || unit.contains("per cent") {
            return "\(value)%"
        }
        if unit.hasPrefix("ms") || unit.contains("millisecond") {
            return "\(value)ms"
        }
        return "\(value) bb"
    }
    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
