import ApplicationServices
import Foundation

/// Dictionary storage, prompt shaping, and post-insert learning.
public final class VocabularyLearner {
    public static let shared = VocabularyLearner()
    public static let didChangeNotification = Notification.Name("VocabularyLearner.didChange")

    private struct Store: Codable {
        var manual: [String]
        var autoLearned: [String]
        var replacements: [VocabularyPostProcessor.Replacement]

        static let empty = Store(manual: [], autoLearned: [], replacements: [])
    }

    private let fileURL: URL
    private var store: Store
    private let queue = DispatchQueue(label: "local-voice.vocab-learn")

    private init() {
        fileURL = Config.configDir.appendingPathComponent("learned-vocabulary.json")
        store = Self.load(from: fileURL)
    }

    public func allTerms() -> [String] {
        queue.sync {
            mergedTerms(manual: store.manual, autoLearned: store.autoLearned)
        }
    }

    public func manualTerms() -> [String] {
        queue.sync { store.manual.sorted() }
    }

    public func replacementRules(
        pokerVocabularyEnabled: Bool = false
    ) -> [VocabularyPostProcessor.Replacement] {
        queue.sync {
            mergedReplacementRulesLocked(
                pokerVocabularyEnabled: pokerVocabularyEnabled
            )
        }
    }

    private func mergedReplacementRules(
        pokerVocabularyEnabled: Bool = false
    ) -> [VocabularyPostProcessor.Replacement] {
        queue.sync {
            mergedReplacementRulesLocked(
                pokerVocabularyEnabled: pokerVocabularyEnabled
            )
        }
    }

    private static let pokerReplacementSources: Set<String> = {
        Set(PokerVocabulary.replacements.map { $0.from.lowercased() })
    }()

    /// Compiled operator rules are always on. Poker rules apply only when the
    /// active capture profile is `poker.exploit`. User-taught rules with
    /// `origin == .user` still win on the same `from` key so Dictionary can
    /// override a bad seed without a rebuild. Stale seeded `to` values are
    /// refreshed on load by `refreshedReplacements`.
    private func mergedReplacementRulesLocked(
        pokerVocabularyEnabled: Bool = false
    ) -> [VocabularyPostProcessor.Replacement] {
        var byFrom: [String: VocabularyPostProcessor.Replacement] = [:]
        var compiled = OperatorVocabulary.replacements
        if pokerVocabularyEnabled {
            compiled += PokerVocabulary.replacements
        }
        for rule in compiled {
            guard Self.isValidReplacementSource(rule.from) else { continue }
            byFrom[rule.from.lowercased()] = rule
        }
        for rule in store.replacements {
            let key = rule.from.lowercased()
            if !pokerVocabularyEnabled,
               Self.pokerReplacementSources.contains(key) {
                continue
            }
            byFrom[key] = rule
        }
        return Array(byFrom.values)
    }

    public func merged(with configTerms: [String]) -> [String] {
        queue.sync {
            // User-added dictionary entries lead: they are the whole point of
            // the Dictionary feature and must not be crowded out of the
            // (length-bounded) prompt by generic seed vocabulary.
            mergedTerms(
                manual: store.manual + configTerms,
                autoLearned: store.autoLearned
            )
        }
    }

    /// Dictionary terms do not go into the Whisper initial prompt. Feeding a
    /// comma-separated word list with `--carry-initial-prompt` strongly biases
    /// the model to hallucinate those tokens (e.g. "are" -> "OGrE"). Use only
    /// explicit post-STT replacement rules instead.
    public func promptString(configTerms: [String], maxCharacters: Int = 224) -> String {
        _ = configTerms
        _ = maxCharacters
        return ""
    }

    public func postProcess(
        _ text: String,
        configTerms: [String] = [],
        visibleSpellings: [String] = [],
        pokerVocabularyEnabled: Bool = false
    ) -> String {
        let boost = safeBoostTerms(
            configTerms: configTerms,
            pokerVocabularyEnabled: pokerVocabularyEnabled
        )
        let applied = VocabularyPostProcessor.apply(
            text,
            replacements: mergedReplacementRules(
                pokerVocabularyEnabled: pokerVocabularyEnabled
            ),
            boostTerms: boost
        )
        let cleaned = DictationCohesion.polish(applied.text)
        let spelled = NearbyContextSampler.applyVisibleSpellings(
            cleaned,
            names: visibleSpellings
        )
        let normalized = pokerVocabularyEnabled
            ? PokerHandNormalizer.apply(spelled)
            : spelled
        return SpokenFigureNormalizer.apply(normalized)
    }

    /// Multi-word manual dictionary entries only. Single-word fuzzy boost
    /// corrupts common English ("man" -> "Kun"); single-word fixes use
    /// explicit `replacements` instead.
    func safeBoostTerms(
        configTerms: [String] = [],
        pokerVocabularyEnabled: Bool = false
    ) -> [String] {
        queue.sync {
            mergedBoostTerms(
                manual: store.manual,
                configTerms: configTerms,
                pokerVocabularyEnabled: pokerVocabularyEnabled
            )
        }
    }

    private func mergedBoostTerms(
        manual: [String],
        configTerms: [String],
        pokerVocabularyEnabled: Bool = false
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        var seeded = OperatorVocabulary.terms
        if pokerVocabularyEnabled {
            seeded += PokerVocabulary.terms
        }
        for term in seeded + manual + configTerms where term.contains(" ") {
            let key = term.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(term)
        }
        return out.sorted { $0.count > $1.count }
    }

    private static let maxReplacementRules = 64

    @discardableResult
    public func addTerm(_ value: String) -> Bool {
        let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidManualTerm(term) else { return false }
        return queue.sync {
            guard !containsTerm(term, in: store.manual) else { return false }
            store.manual.append(term)
            store.manual.sort()
            persist()
            notifyChanged()
            return true
        }
    }

    @discardableResult
    public func removeTerm(_ value: String) -> Bool {
        queue.sync {
            let beforeManual = store.manual.count
            store.manual.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
            let beforeAuto = store.autoLearned.count
            store.autoLearned.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
            store.replacements.removeAll {
                $0.from.caseInsensitiveCompare(value) == .orderedSame
                    || $0.to.caseInsensitiveCompare(value) == .orderedSame
            }
            let changed = beforeManual != store.manual.count
                || beforeAuto != store.autoLearned.count
            if changed {
                persist()
                notifyChanged()
            }
            return changed
        }
    }

    @discardableResult
    public func addReplacement(from: String, to: String) -> Bool {
        let source = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidReplacementSource(source), Self.isValidManualTerm(target) else { return false }
        return queue.sync {
            store.replacements.removeAll { $0.from.caseInsensitiveCompare(source) == .orderedSame }
            store.replacements.append(.init(from: source, to: target, origin: .user))
            persist()
            notifyChanged()
            return true
        }
    }

    @discardableResult
    public func purgeAutoLearned() -> Int {
        queue.sync {
            let count = store.autoLearned.count
            guard count > 0 else { return 0 }
            store.autoLearned.removeAll()
            persist()
            notifyChanged()
            return count
        }
    }

    public func observeCorrection(inserted: String, polished: String, delay: TimeInterval = 2.5) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard let current = Self.readFocusedText(), !current.isEmpty else { return }
            guard current != polished, current != inserted else { return }
            if let pair = DictationTeacher.proposedReplacement(inserted: polished, edited: current)
                ?? DictationTeacher.proposedReplacement(inserted: inserted, edited: current) {
                _ = self.addReplacement(from: pair.from, to: pair.to)
                return
            }
            let newTerms = Self.extractNewTerms(from: polished, to: current)
            guard !newTerms.isEmpty else { return }
            self.queue.sync {
                var added: [String] = []
                for term in newTerms where Self.isValidAutoLearnedTerm(term) {
                    guard !self.containsTerm(term, in: self.store.manual + self.store.autoLearned) else { continue }
                    self.store.autoLearned.append(term)
                    added.append(term)
                }
                guard !added.isEmpty else { return }
                self.persist()
                self.notifyChanged()
                fputs("VocabularyLearner: learned \(added.joined(separator: ", "))\n", stderr)
            }
        }
    }

    public func learnFromDiff(raw: String, polished: String) {
        let newTerms = Self.extractNewTerms(from: raw, to: polished)
        guard !newTerms.isEmpty else { return }
        queue.sync {
            var added: [String] = []
            for term in newTerms where Self.isValidAutoLearnedTerm(term) {
                guard !containsTerm(term, in: store.manual + store.autoLearned) else { continue }
                store.autoLearned.append(term)
                added.append(term)
            }
            guard !added.isEmpty else { return }
            persist()
            notifyChanged()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    private func mergedTerms(manual: [String], autoLearned: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for term in manual + autoLearned where !term.isEmpty {
            let key = term.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(term)
        }
        return out
    }

    private func containsTerm(_ term: String, in list: [String]) -> Bool {
        list.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
    }

    private static func load(from url: URL) -> Store {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let loaded: Store
        if let store = try? JSONDecoder().decode(Store.self, from: data) {
            loaded = store
        } else if let legacy = try? JSONDecoder().decode([String].self, from: data) {
            var manual: [String] = []
            var autoLearned: [String] = []
            for term in legacy {
                if isValidManualTerm(term) {
                    manual.append(term)
                } else if isValidAutoLearnedTerm(term) {
                    autoLearned.append(term)
                }
            }
            loaded = Store(manual: manual, autoLearned: autoLearned, replacements: [])
        } else {
            return .empty
        }

        let sanitized = sanitize(loaded)
        let pruned = prunePollutedManualTerms(sanitized)
        let seeded = seedOperatorTerms(pruned)
        if seeded.manual != loaded.manual
            || seeded.autoLearned != loaded.autoLearned
            || seeded.replacements != loaded.replacements {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let encoded = try? JSONEncoder().encode(seeded) {
                try? encoded.write(to: url)
            }
        }
        return seeded
    }

    private static func seedOperatorTerms(_ store: Store) -> Store {
        var next = store
        for term in OperatorVocabulary.terms where isValidManualTerm(term) {
            let exists = next.manual.contains {
                $0.caseInsensitiveCompare(term) == .orderedSame
            }
            if !exists { next.manual.append(term) }
        }
        next.manual.sort()
        next.replacements = refreshedReplacements(existing: next.replacements)
        return next
    }

    /// Refresh compiled `to` values. Keep a stored rule only when the operator
    /// explicitly taught it (`origin == .user`). Missing `origin` is treated as
    /// a stale seed — that is how older JSON files are encoded.
    static func refreshedReplacements(
        existing: [VocabularyPostProcessor.Replacement]
    ) -> [VocabularyPostProcessor.Replacement] {
        var byFrom: [String: VocabularyPostProcessor.Replacement] = [:]
        for rule in existing {
            byFrom[rule.from.lowercased()] = rule
        }
        for rule in OperatorVocabulary.replacements {
            guard isValidReplacementSource(rule.from), isValidManualTerm(rule.to) else {
                continue
            }
            let key = rule.from.lowercased()
            if let current = byFrom[key], current.origin == .user {
                continue
            }
            byFrom[key] = .init(from: rule.from, to: rule.to, origin: .seeded)
        }
        return Array(byFrom.values)
    }

    /// True when every word in the span is high-frequency English that must
    /// never be rewritten by dictionary correction.
    static func isCommonEnglishSpan(_ span: String) -> Bool {
        let words = span
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }
        return words.allSatisfy { commonDictationTokens.contains($0) }
    }

    private static let commonDictationTokens: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "do", "for", "go",
        "he", "if", "in", "is", "it", "man", "me", "my", "no", "of", "oh", "ok", "on", "or",
        "our", "so", "the", "to", "up", "we", "you", "add", "again", "all", "also",
        "always", "and", "ask", "can", "come", "did", "for", "get", "had", "has",
        "have", "here", "hey", "how", "just", "like", "make", "not", "now", "one",
        "say", "see", "she", "that", "them", "then", "there", "they", "this", "use",
        "was", "what", "when", "will", "with", "work", "would", "yeah", "your",
        "about", "talking",
    ]

    /// Older builds promoted auto-learned session junk into `manual`. When the
    /// list is obviously polluted, keep only high-confidence human vocabulary.
    private static func prunePollutedManualTerms(_ store: Store) -> Store {
        guard store.manual.count > 32 else { return store }
        let kept = store.manual.filter(isHighConfidenceManualTerm)
        guard kept.count < store.manual.count else { return store }
        return Store(
            manual: kept.sorted(),
            autoLearned: store.autoLearned.filter(isValidAutoLearnedTerm),
            replacements: store.replacements
        )
    }

    static func isHighConfidenceManualTerm(_ term: String) -> Bool {
        guard isValidManualTerm(term) else { return false }
        if term.contains(" ") { return true }
        if term.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        if term.dropFirst().contains(where: \.isUppercase) { return true }
        let lower = term.lowercased()
        if commonDictationTokens.contains(lower) { return false }
        if term == term.uppercased(),
           (2...5).contains(term.filter(\.isLetter).count),
           term.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-")).contains($0) }) {
            return true
        }
        if term == term.uppercased(), term.count <= 8 { return false }
        if term.count <= 8,
           term.first?.isUppercase == true,
           term.dropFirst().allSatisfy({ $0.isLowercase || !$0.isLetter }) {
            return true
        }
        return false
    }

    private static func sanitize(_ store: Store) -> Store {
        Store(
            manual: store.manual.filter(isValidManualTerm),
            autoLearned: store.autoLearned.filter(isValidAutoLearnedTerm),
            replacements: store.replacements.filter {
                isValidReplacementSource($0.from) && isValidManualTerm($0.to)
            }
        )
    }

    /// Replacement sources must be deliberate misspellings, not common English.
    static func isValidReplacementSource(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidManualTerm(trimmed) else { return false }
        if isCommonEnglishSpan(trimmed) { return false }
        if trimmed.contains(" ") {
            let words = trimmed
                .lowercased()
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            let nonCommon = words.filter { !commonDictationTokens.contains($0) }
            return !nonCommon.isEmpty
        }
        return !commonDictationTokens.contains(trimmed.lowercased())
    }

    static func isValidManualTerm(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(trimmed.count) else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        return !isGarbage(trimmed) && looksLikeHumanVocabulary(trimmed)
    }

    static func isValidAutoLearnedTerm(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...60).contains(trimmed.count) else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        guard trimmed.first?.isUppercase == true || trimmed.contains(" ") else { return false }
        return !isGarbage(trimmed) && looksLikeHumanVocabulary(trimmed)
    }

    private static func looksLikeHumanVocabulary(_ term: String) -> Bool {
        if term.range(of: #"^\d-bet$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if term.range(of: #"^\dbet$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if term.range(of: #"^\d[A-Z]{1,3}$"#, options: .regularExpression) != nil {
            return true
        }
        if term.range(of: #"^\d"#, options: .regularExpression) != nil { return false }
        if term.range(of: #"^\d+[a-z]{0,2}$"#, options: .regularExpression) != nil { return false }
        if term.range(of: #"\d+(ms|s|k|p|M)$"#, options: .regularExpression) != nil { return false }
        if term.range(of: #"^[A-F0-9]{6,}$"#, options: .regularExpression) != nil { return false }
        if term.range(of: #"^[A-Za-z0-9+/]{12,}$"#, options: .regularExpression) != nil { return false }
        if term.count <= 3, term == term.uppercased(), term.rangeOfCharacter(from: .decimalDigits) != nil {
            return false
        }
        let letters = term.filter(\.isLetter).count
        return letters >= max(1, term.count / 3)
    }

    private static func isGarbage(_ term: String) -> Bool {
        if term.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) { return true }
        if term.range(of: #"^[0-9A-Fa-f]{6,}$"#, options: .regularExpression) != nil { return true }
        if term.range(of: #"^[A-Za-z0-9]{8,}$"#, options: .regularExpression) != nil,
           term.rangeOfCharacter(from: .lowercaseLetters) == nil
            || term.filter({ $0.isNumber }).count >= 3 {
            return true
        }
        if term.hasPrefix("u2019") { return true }
        return false
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
        let beforeTokens = Set(tokenize(before).map { $0.lowercased() })
        var out: [String] = []
        for token in tokenize(after) {
            if beforeTokens.contains(token.lowercased()) { continue }
            out.append(token)
        }
        return Array(Set(out))
    }

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}
