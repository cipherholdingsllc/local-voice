import ApplicationServices
import Foundation

/// Learn vocabulary from post-insert corrections (#8).
public final class VocabularyLearner {
    public static let shared = VocabularyLearner()

    private let fileURL: URL
    private var terms: Set<String>
    private let queue = DispatchQueue(label: "local-flow.vocab-learn")

    private init() {
        fileURL = Config.configDir.appendingPathComponent("learned-vocabulary.json")
        terms = Self.load(from: fileURL)
    }

    public func allTerms() -> [String] {
        queue.sync { Array(terms).sorted() }
    }

    public func merged(with configTerms: [String]) -> [String] {
        let learned = allTerms()
        var seen = Set<String>()
        var out: [String] = []
        for t in configTerms + learned where !t.isEmpty && !seen.contains(t.lowercased()) {
            seen.insert(t.lowercased())
            out.append(t)
        }
        return out
    }

    /// Schedule observation: after insert, read focused field and diff against polished text.
    public func observeCorrection(inserted: String, polished: String, delay: TimeInterval = 2.5) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard let current = Self.readFocusedText(), !current.isEmpty else { return }
            guard current != polished, current != inserted else { return }
            let newTerms = Self.extractNewTerms(from: polished, to: current)
            guard !newTerms.isEmpty else { return }
            self.queue.sync {
                for t in newTerms { self.terms.insert(t) }
                self.persist()
            }
            fputs("VocabularyLearner: learned \(newTerms.joined(separator: ", "))\n", stderr)
        }
    }

    /// Log raw→polished diff for explicit learning.
    public func learnFromDiff(raw: String, polished: String) {
        let newTerms = Self.extractNewTerms(from: raw, to: polished)
        guard !newTerms.isEmpty else { return }
        queue.sync {
            for t in newTerms { terms.insert(t) }
            persist()
        }
    }

    private func persist() {
        let arr = Array(terms).sorted()
        guard let data = try? JSONEncoder().encode(arr) else { return }
        try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }

    private static func load(from url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    private static func readFocusedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        let ax = element as! AXUIElement
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(ax, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }

    private static func extractNewTerms(from before: String, to after: String) -> [String] {
        let beforeTokens = Set(tokenize(before))
        var out: [String] = []
        for token in tokenize(after) {
            if token.count < 2 { continue }
            if beforeTokens.contains(token.lowercased()) { continue }
            if token.first?.isUppercase == true || token.contains(where: { $0.isNumber }) {
                out.append(token)
            }
        }
        return Array(Set(out))
    }

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}
