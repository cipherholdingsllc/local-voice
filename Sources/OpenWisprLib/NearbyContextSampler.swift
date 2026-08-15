import ApplicationServices
import Foundation

/// Local-only nearby-text spelling, the honest subset of Wispr's
/// "context awareness" that does not leave the device.
///
/// Wispr reads nearby cursor text, app chrome, and sometimes a screenshot,
/// then sends that context with the audio. We only read the focused field
/// and window title through Accessibility, extract likely proper nouns, and
/// restore their spelling on this take. Nothing is persisted or uploaded.
public enum NearbyContextSampler {
    public static func sampleVisibleSpellings(limit: Int = 16) -> [String] {
        let blobs = [readFocusedText(), readFocusedWindowTitle()]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var out: [String] = []
        for blob in blobs {
            for name in extractProperNouns(from: blob) {
                let key = name.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(name)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    public static func extractProperNouns(from text: String) -> [String] {
        let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var out: [String] = []
        var seen = Set<String>()
        for (index, token) in tokens.enumerated() {
            guard token.count >= 3 else { continue }
            guard token.first?.isLetter == true else { continue }
            let lower = token.lowercased()
            if VocabularyLearner.isCommonEnglishSpan(lower) { continue }
            let capitalized = token.first?.isUppercase == true
                && token.dropFirst().allSatisfy { !$0.isLetter || $0.isLowercase }
            // Skip sentence-initial common words that happen to be capitalized.
            if index == 0, capitalized, VocabularyLearner.isCommonEnglishSpan(lower) {
                continue
            }
            guard capitalized else { continue }
            guard !seen.contains(lower) else { continue }
            seen.insert(lower)
            out.append(token)
        }
        return out
    }

    public static func applyVisibleSpellings(_ text: String, names: [String]) -> String {
        guard !text.isEmpty, !names.isEmpty else { return text }
        var result = text
        let sorted = names
            .filter { $0.count >= 3 && !VocabularyLearner.isCommonEnglishSpan($0) }
            .sorted { $0.count > $1.count }
        for name in sorted {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: name
            )
        }
        return result
    }

    private static func readFocusedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let element = focused else { return nil }
        let ax = element as! AXUIElement
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            ax,
            kAXValueAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private static func readFocusedWindowTitle() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let element = focused else { return nil }
        let ax = element as! AXUIElement
        var windowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            ax,
            kAXWindowAttribute as CFString,
            &windowRef
        ) == .success, let window = windowRef else { return nil }
        let windowEl = window as! AXUIElement
        var title: AnyObject?
        guard AXUIElementCopyAttributeValue(
            windowEl,
            kAXTitleAttribute as CFString,
            &title
        ) == .success else { return nil }
        return title as? String
    }
}
