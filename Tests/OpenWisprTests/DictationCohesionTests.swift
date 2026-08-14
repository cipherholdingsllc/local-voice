import XCTest
@testable import OpenWisprLib

final class DictationCohesionTests: XCTestCase {
    func testStripsUmAndUhWithoutChangingMeaning() {
        let raw = "Um, so yeah, let's try this. Hey do Fable, GPT, CipherOS, OGrE."
        XCTAssertEqual(
            DictationCohesion.polish(raw),
            "So yeah, let's try this. Hey do Fable, GPT, CipherOS, OGrE."
        )
    }

    func testStripsRepeatedUhInTheMiddle() {
        let raw = "get set up with the uh with the Apple Silicon MLX"
        XCTAssertEqual(
            DictationCohesion.polish(raw),
            "Get set up with the with the Apple Silicon MLX"
        )
    }

    func testKeepsLikeWhenItCarriesMeaning() {
        XCTAssertEqual(
            DictationCohesion.polish("I like this"),
            "I like this"
        )
        XCTAssertEqual(
            DictationCohesion.polish("it was like the same books"),
            "It was like the same books"
        )
    }

    func testRemovesCommaWrappedLike() {
        XCTAssertEqual(
            DictationCohesion.polish("do like, an adversarial pass"),
            "Do like, an adversarial pass"
        )
        XCTAssertEqual(
            DictationCohesion.polish("do, like, an adversarial pass"),
            "Do, an adversarial pass"
        )
    }

    func testScratchThatDropsThePriorClause() {
        XCTAssertEqual(
            DictationCohesion.polish("send it to Dylan scratch that send it to Andras"),
            "Send it to Andras"
        )
    }

    func testInTheSurvivesCohesion() {
        let sentence =
            "Would it land in the real ledger as well as Laird getting a text?"
        XCTAssertEqual(DictationCohesion.polish(sentence), sentence)
    }
}

final class OperatorVocabularyTests: XCTestCase {
    func testCypherBecomesCipher() {
        let result = VocabularyPostProcessor.apply(
            "use Cypher OS daily",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "use CipherOS daily")
    }

    func testGetHubsBecomesGitHub() {
        let result = VocabularyPostProcessor.apply(
            "smelt these get hubs",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "smelt these GitHub")
    }

    func testOgreBecomesOGrE() {
        let result = VocabularyPostProcessor.apply(
            "the ogre layer",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "the OGrE layer")
    }

    func testOperatorRulesNeverRewriteInThe() {
        let result = VocabularyPostProcessor.apply(
            "Would it land in the real ledger as well as Laird getting a text?",
            replacements: OperatorVocabulary.replacements,
            boostTerms: OperatorVocabulary.terms.filter { $0.contains(" ") }
        )
        XCTAssertEqual(
            result.text,
            "Would it land in the real ledger as well as Laird getting a text?"
        )
    }

    func testNoOperatorReplacementSourceIsCommonEnglish() {
        for rule in OperatorVocabulary.replacements {
            XCTAssertTrue(
                VocabularyLearner.isValidReplacementSource(rule.from),
                "unsafe replacement source: \(rule.from)"
            )
            XCTAssertFalse(
                VocabularyLearner.isCommonEnglishSpan(rule.from),
                "common English replacement: \(rule.from)"
            )
        }
    }
}
