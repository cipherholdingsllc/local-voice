import Foundation

/// Poker terminology for Local Voice, including future Exploit Poker takes.
///
/// Proper nouns, acronyms, and multi-word jargon only. Common verbs
/// (fold, call, raise, check, bet) and streets (flop, turn, river) are
/// left alone so normal English is not rewritten.
public enum PokerVocabulary {
    public static let terms: [String] = [
        "Exploit Poker",
        "PokerGod",
        "NLHE",
        "NLH",
        "PLO",
        "PLO5",
        "MTT",
        "SNG",
        "PKO",
        "UTG",
        "UTG+1",
        "UTG+2",
        "EP",
        "MP",
        "LJ",
        "HJ",
        "CO",
        "BTN",
        "SB",
        "BB",
        "HU",
        "MW",
        "GTO",
        "ICM",
        "SPR",
        "EV",
        "EVbb",
        "IP",
        "OOP",
        "OESD",
        "NFD",
        "BDFD",
        "BDOSD",
        "SRP",
        "3BP",
        "4BP",
        "MDF",
        "RFI",
        "VPIP",
        "PFR",
        "WTSD",
        "WWSF",
        "ATS",
        "ROI",
        "ITM",
        "CEV",
        "TAG",
        "LAG",
        "3B",
        "F3B",
        "CB",
        "FCB",
        "c-bet",
        "3-bet",
        "4-bet",
        "5-bet",
        "check-raise",
        "donk bet",
        "value bet",
        "probe bet",
        "range bet",
        "continuation bet",
        "delayed c-bet",
        "under the gun",
        "low jack",
        "lojack",
        "high jack",
        "hijack",
        "cutoff",
        "small blind",
        "big blind",
        "big blinds",
        "in position",
        "out of position",
        "pot odds",
        "implied odds",
        "reverse implied odds",
        "fold equity",
        "nut flush",
        "nut flush draw",
        "flush draw",
        "backdoor flush draw",
        "gutshot",
        "open-ended",
        "straight draw",
        "combo draw",
        "overpair",
        "underpair",
        "top pair",
        "middle pair",
        "two pair",
        "set mining",
        "suited connector",
        "offsuit",
        "preflop",
        "heads-up",
        "short stacked",
        "deep stacked",
        "effective stack",
        "pot committed",
        "open raise",
        "isolation",
        "blocker",
        "range advantage",
        "nut advantage",
        "calling station",
        "bluff catcher",
        "free card",
        "multiway",
        "straddle",
        "overlimp",
        "limp reraise",
        "single raised pot",
        "three bet pot",
        "four bet pot",
        "minimum defense frequency",
        "stack to pot ratio",
        "no limit hold em",
        "pot limit omaha",
        "final table",
        "on the bubble",
        "mystery bounty",
        "the nuts",
        "second nuts",
        "drawing dead",
        "board texture",
        "wet board",
        "dry board",
        "paired board",
        "monotone",
        "two-tone",
        "rainbow board",
        "double barrel",
        "triple barrel",
        "overbet",
        "underbet",
        "min-raise",
        "jam",
        "shove",
        "cooler",
        "bad beat",
        "solver",
        "node lock",
        "GTO Wizard",
        "bb/100",
    ]

    /// Spoken jargon and phonetics only. Ordinary English phrases such as
    /// "the button", "in position", "cut off", and "cold call" stay intact.
    public static let replacements: [VocabularyPostProcessor.Replacement] = [
        .init(from: "you tee gee", to: "UTG"),
        .init(from: "you tg", to: "UTG"),
        .init(from: "under the gun plus one", to: "UTG+1"),
        .init(from: "under the gun plus 1", to: "UTG+1"),
        .init(from: "under the gun + 1", to: "UTG+1"),
        .init(from: "under the gun plus two", to: "UTG+2"),
        .init(from: "under the gun plus 2", to: "UTG+2"),
        .init(from: "under the gun + 2", to: "UTG+2"),
        .init(from: "under the gun", to: "UTG"),
        .init(from: "you tee gee plus one", to: "UTG+1"),
        .init(from: "you tee gee plus two", to: "UTG+2"),
        .init(from: "utg plus one", to: "UTG+1"),
        .init(from: "utg plus 1", to: "UTG+1"),
        .init(from: "utg + 1", to: "UTG+1"),
        .init(from: "utg plus two", to: "UTG+2"),
        .init(from: "utg plus 2", to: "UTG+2"),
        .init(from: "utg + 2", to: "UTG+2"),
        .init(from: "low jack", to: "LJ"),
        .init(from: "lo jack", to: "LJ"),
        .init(from: "lojack", to: "LJ"),
        .init(from: "lowjack", to: "LJ"),
        .init(from: "low-jack", to: "LJ"),
        .init(from: "lo-jack", to: "LJ"),
        .init(from: "l jack", to: "LJ"),
        .init(from: "the low jack", to: "LJ"),
        .init(from: "the lojack", to: "LJ"),
        .init(from: "in the low jack", to: "in the LJ"),
        .init(from: "in the lojack", to: "in the LJ"),
        .init(from: "high jack", to: "HJ"),
        .init(from: "hi jack", to: "HJ"),
        .init(from: "highjack", to: "HJ"),
        .init(from: "high-jack", to: "HJ"),
        .init(from: "h jack", to: "HJ"),
        .init(from: "hijack", to: "HJ"),
        .init(from: "the high jack", to: "HJ"),
        .init(from: "in the high jack", to: "in the HJ"),
        .init(from: "the hijack", to: "HJ"),
        .init(from: "in the hijack", to: "in the HJ"),
        .init(from: "the cutoff", to: "the CO"),
        .init(from: "in the cutoff", to: "in the CO"),
        .init(from: "dealer button", to: "BTN"),
        .init(from: "on the button", to: "on the BTN"),
        .init(from: "in the small blind", to: "in the SB"),
        .init(from: "in the big blind", to: "in the BB"),
        .init(from: "big blinds", to: "bb"),
        .init(from: "three bet", to: "3-bet"),
        .init(from: "3 bet", to: "3-bet"),
        .init(from: "three-bet", to: "3-bet"),
        .init(from: "four bet", to: "4-bet"),
        .init(from: "for bet", to: "4-bet"),
        .init(from: "4 bet", to: "4-bet"),
        .init(from: "four-bet", to: "4-bet"),
        .init(from: "all in", to: "all-in"),
        .init(from: "five bet", to: "5-bet"),
        .init(from: "5 bet", to: "5-bet"),
        .init(from: "continuation bet", to: "c-bet"),
        .init(from: "c bet", to: "c-bet"),
        .init(from: "see bet", to: "c-bet"),
        .init(from: "delayed c bet", to: "delayed c-bet"),
        .init(from: "check raise", to: "check-raise"),
        .init(from: "out of position", to: "OOP"),
        .init(from: "g t o", to: "GTO"),
        .init(from: "gto wizard", to: "GTO Wizard"),
        .init(from: "i c m", to: "ICM"),
        .init(from: "s p r", to: "SPR"),
        .init(from: "stack to pot ratio", to: "SPR"),
        .init(from: "expected value", to: "EV"),
        .init(from: "fold equity", to: "FE"),
        .init(from: "open-ended straight draw", to: "OESD"),
        .init(from: "open ended straight draw", to: "OESD"),
        .init(from: "o e s d", to: "OESD"),
        .init(from: "oesd", to: "OESD"),
        .init(from: "nut flush draw", to: "NFD"),
        .init(from: "backdoor flush draw", to: "BDFD"),
        .init(from: "gut shot", to: "gutshot"),
        .init(from: "off suit", to: "offsuit"),
        .init(from: "pre flop", to: "preflop"),
        .init(from: "heads up", to: "heads-up"),
        .init(from: "exploit poker", to: "Exploit Poker"),
        .init(from: "poker god", to: "PokerGod"),
        .init(from: "three bet pot", to: "3BP"),
        .init(from: "four bet pot", to: "4BP"),
        .init(from: "single raised pot", to: "SRP"),
        .init(from: "minimum defense frequency", to: "MDF"),
        .init(from: "over pair", to: "overpair"),
        .init(from: "iso raise", to: "isolation"),
        .init(from: "isolation raise", to: "isolation"),
        .init(from: "no limit hold em", to: "NLHE"),
        .init(from: "no limit holdem", to: "NLHE"),
        .init(from: "pot limit omaha", to: "PLO"),
        .init(from: "pot committed", to: "pot committed"),
        .init(from: "set mining", to: "set mining"),
        .init(from: "suited connector", to: "suited connector"),
        .init(from: "calling station", to: "calling station"),
        .init(from: "bluff catcher", to: "bluff catcher"),
        .init(from: "range advantage", to: "range advantage"),
        .init(from: "nut advantage", to: "nut advantage"),
        .init(from: "implied odds", to: "implied odds"),
        .init(from: "reverse implied odds", to: "reverse implied odds"),
        .init(from: "effective stack", to: "effective stack"),
        .init(from: "double barrel", to: "double barrel"),
        .init(from: "triple barrel", to: "triple barrel"),
        .init(from: "min raise", to: "min-raise"),
        .init(from: "node lock", to: "node lock"),
        .init(from: "b b per 100", to: "bb/100"),
        .init(from: "big blinds per 100", to: "bb/100"),
    ]
}

/// Spoken hand names to compact poker notation for training notes.
///
/// `s` is spades, not "suited". "jack nine" -> `J9`. A named suit
/// ("clubs", "spades", "hearts", "diamonds") appends `c`/`s`/`h`/`d`.
/// Bare number-number pairs ("ten five") stay words so "ten five-gallon"
/// is not rewritten. Offsuit still uses `o`. Pocket aces -> `AA`.
public enum PokerHandNormalizer {
    private static let ranks: [(String, String)] = [
        ("aces", "A"), ("ace", "A"),
        ("kings", "K"), ("king", "K"),
        ("queens", "Q"), ("queen", "Q"),
        ("jacks", "J"), ("jack", "J"),
        ("tens", "T"), ("ten", "T"),
        ("nines", "9"), ("nine", "9"),
        ("eights", "8"), ("eight", "8"),
        ("sevens", "7"), ("seven", "7"),
        ("sixes", "6"), ("six", "6"),
        ("fives", "5"), ("five", "5"),
        ("fours", "4"), ("four", "4"),
        ("threes", "3"), ("treys", "3"), ("three", "3"), ("trey", "3"),
        ("deuces", "2"), ("twos", "2"), ("deuce", "2"), ("two", "2"),
    ]

    private static let suits: [(String, String)] = [
        ("clubs", "c"), ("club", "c"),
        ("spades", "s"), ("spade", "s"),
        ("hearts", "h"), ("heart", "h"),
        ("diamonds", "d"), ("diamond", "d"),
    ]

    private static let faceLetters: Set<String> = ["A", "K", "Q", "J"]
    private static let rankByWord: [String: String] = Dictionary(uniqueKeysWithValues: ranks)
    private static let suitByWord: [String: String] = Dictionary(uniqueKeysWithValues: suits)
    private static let rankAlt = alternation(ranks.map(\.0))
    private static let suitAlt = alternation(suits.map(\.0))

    private static let pocketRegex = compile("(?i)\\bpocket (\(rankAlt))\\b")
    private static let twoSuitOfRegex = compile(
        "(?i)\\b(\(rankAlt)) of (\(suitAlt)) (\(rankAlt)) of (\(suitAlt))\\b"
    )
    private static let twoSuitSpaceRegex = compile(
        "(?i)\\b(\(rankAlt)) (\(suitAlt)) (\(rankAlt)) (\(suitAlt))\\b"
    )
    private static let suitedSuitRegex = compile(
        "(?i)\\b(\(rankAlt)) (\(rankAlt)) suited (\(suitAlt))\\b"
    )
    private static let ofSuitRegex = compile("(?i)\\b(\(rankAlt)) (\(rankAlt)) of (\(suitAlt))\\b")
    private static let trailingSuitRegex = compile("(?i)\\b(\(rankAlt)) (\(rankAlt)) (\(suitAlt))\\b")
    private static let offsuitRegex = compile("(?i)\\b(\(rankAlt)) (\(rankAlt)) offsuit\\b")
    private static let offSuitRegex = compile("(?i)\\b(\(rankAlt)) (\(rankAlt)) off suit\\b")
    private static let suitedRegex = compile("(?i)\\b(\(rankAlt)) (\(rankAlt)) suited\\b")
    private static let barePairRegex = compile("(?i)\\b(\(rankAlt)) (\(rankAlt))\\b")

    public static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = rewrite(pocketRegex, in: text) { match in
            guard let rank = letter(match[1], in: rankByWord) else { return nil }
            return rank + rank
        }
        result = rewrite(twoSuitOfRegex, in: result) { twoSuit($0) }
        result = rewrite(twoSuitSpaceRegex, in: result) { twoSuit($0) }
        result = rewrite(suitedSuitRegex, in: result) { sameSuit($0) }
        result = rewrite(ofSuitRegex, in: result) { sameSuit($0) }
        result = rewrite(trailingSuitRegex, in: result) { sameSuit($0) }
        result = rewrite(offsuitRegex, in: result) { pair($0, suffix: "o") }
        result = rewrite(offSuitRegex, in: result) { pair($0, suffix: "o") }
        result = rewrite(suitedRegex, in: result) { pair($0, suffix: "") }
        result = rewrite(barePairRegex, in: result) { groups in
            guard let left = letter(groups[1], in: rankByWord),
                  let right = letter(groups[2], in: rankByWord),
                  left != right,
                  faceLetters.contains(left) || faceLetters.contains(right)
            else { return nil }
            return canonical(left, right, "")
        }
        return result
    }

    private static func twoSuit(_ groups: [String]) -> String? {
        guard groups.count >= 5,
              let r1 = letter(groups[1], in: rankByWord),
              let s1 = letter(groups[2], in: suitByWord),
              let r2 = letter(groups[3], in: rankByWord),
              let s2 = letter(groups[4], in: suitByWord),
              r1 != r2
        else { return nil }
        if s1 == s2 {
            return canonical(r1, r2, s1)
        }
        let order = "AKQJT98765432"
        guard let i1 = order.firstIndex(of: Character(r1)),
              let i2 = order.firstIndex(of: Character(r2)) else {
            return r1 + s1 + r2 + s2
        }
        if i1 <= i2 {
            return r1 + s1 + r2 + s2
        }
        return r2 + s2 + r1 + s1
    }

    private static func sameSuit(_ groups: [String]) -> String? {
        guard groups.count >= 4,
              let left = letter(groups[1], in: rankByWord),
              let right = letter(groups[2], in: rankByWord),
              let suit = letter(groups[3], in: suitByWord),
              left != right
        else { return nil }
        return canonical(left, right, suit)
    }

    private static func pair(_ groups: [String], suffix: String) -> String? {
        guard groups.count >= 3,
              let left = letter(groups[1], in: rankByWord),
              let right = letter(groups[2], in: rankByWord),
              left != right
        else { return nil }
        return canonical(left, right, suffix)
    }

    private static func canonical(_ a: String, _ b: String, _ suffix: String) -> String {
        let order = "AKQJT98765432"
        guard let ai = order.firstIndex(of: Character(a)),
              let bi = order.firstIndex(of: Character(b)) else {
            return a + b + suffix
        }
        if ai <= bi {
            return a + b + suffix
        }
        return b + a + suffix
    }

    private static func letter(_ word: String, in map: [String: String]) -> String? {
        map[word.lowercased()]
    }

    private static func alternation(_ words: [String]) -> String {
        words
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
    }

    private static func compile(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static func rewrite(
        _ regex: NSRegularExpression?,
        in text: String,
        template: ([String]) -> String?
    ) -> String {
        guard let regex else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var output = text
        for match in matches.reversed() {
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let range = match.range(at: i)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            guard let replacement = template(groups),
                  let whole = Range(match.range, in: output)
            else { continue }
            output.replaceSubrange(whole, with: replacement)
        }
        return output
    }
}
