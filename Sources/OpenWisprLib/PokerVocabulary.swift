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
        "lojack",
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
        .init(from: "under the gun", to: "UTG"),
        .init(from: "utg plus one", to: "UTG+1"),
        .init(from: "utg + 1", to: "UTG+1"),
        .init(from: "utg plus two", to: "UTG+2"),
        .init(from: "low jack", to: "LJ"),
        .init(from: "lo jack", to: "LJ"),
        .init(from: "lojack", to: "LJ"),
        .init(from: "high jack", to: "HJ"),
        .init(from: "the hijack", to: "the HJ"),
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
        .init(from: "4 bet", to: "4-bet"),
        .init(from: "four-bet", to: "4-bet"),
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
/// Bare rank pairs ("ten five") are not rewritten; that collides with
/// ordinary English ("ten five-gallon"). Pocket / suited / offsuit only.
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

    public static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for (word, letter) in ranks {
            let pocket = "(?i)\\bpocket \(word)\\b"
            result = replace(pocket, with: letter + letter, in: result)
        }
        for left in ranks {
            for right in ranks {
                if left.1 == right.1 { continue }
                let suited = "(?i)\\b\(left.0) \(right.0) suited\\b"
                result = replace(suited, with: canonical(left.1, right.1, "s"), in: result)
                let offsuit = "(?i)\\b\(left.0) \(right.0) offsuit\\b"
                result = replace(offsuit, with: canonical(left.1, right.1, "o"), in: result)
                let offSuitWords = "(?i)\\b\(left.0) \(right.0) off suit\\b"
                result = replace(offSuitWords, with: canonical(left.1, right.1, "o"), in: result)
            }
        }
        return result
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

    private static func replace(_ pattern: String, with template: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
