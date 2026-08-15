import XCTest
@testable import OpenWisprLib

final class DictationTeacherTests: XCTestCase {
    func testRememberThatPhrase() {
        let remembered = DictationTeacher.parse("remember that koon chan is Kun Chen")
        XCTAssertEqual(remembered.lessons.first?.from, "koon chan")
        XCTAssertEqual(remembered.lessons.first?.to, "Kun Chen")
        XCTAssertEqual(remembered.remainder, "")

        let learned = DictationTeacher.parse("learn that under the gun is UTG")
        XCTAssertEqual(learned.lessons.first?.from, "under the gun")
        XCTAssertEqual(learned.lessons.first?.to, "UTG")

        let added = DictationTeacher.parse("add local voice as Local Voice")
        XCTAssertEqual(added.lessons.first?.from, "local voice")
        XCTAssertEqual(added.lessons.first?.to, "Local Voice")

        XCTAssertTrue(DictationTeacher.parse("remember to pick up milk").lessons.isEmpty)
        XCTAssertTrue(DictationTeacher.parse("in the ledger").lessons.isEmpty)
    }

    func testFieldEditLearnsShortReplacement() {
        let learned = DictationTeacher.proposedReplacement(
            inserted: "koon chan showed up",
            edited: "Kun Chen showed up"
        )
        XCTAssertEqual(learned?.from, "koon chan")
        XCTAssertEqual(learned?.to, "Kun Chen")
    }

    func testFieldEditDoesNotLearnCommonEnglish() {
        XCTAssertNil(DictationTeacher.proposedReplacement(
            inserted: "in the ledger",
            edited: "Kun Chen ledger"
        ))
        XCTAssertNil(DictationTeacher.proposedReplacement(
            inserted: "he's my number one guy",
            edited: "he's my number one pal"
        ))
        XCTAssertNil(DictationTeacher.proposedReplacement(
            inserted: "hello world",
            edited: "hello world extra words I typed"
        ))
    }

    func testHighJackAndLowJackBecomeSeats() {
        let result = VocabularyPostProcessor.apply(
            "high jack and hijack and h jack then low jack and lojack",
            replacements: PokerVocabulary.replacements
        )
        XCTAssertEqual(result.text, "HJ and HJ and HJ then LJ and LJ")

        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "the high jack",
                replacements: PokerVocabulary.replacements
            ).text,
            "HJ"
        )
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "hi jack opens",
                replacements: PokerVocabulary.replacements
            ).text,
            "HJ opens"
        )
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "highjack raises",
                replacements: PokerVocabulary.replacements
            ).text,
            "HJ raises"
        )
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "I am in the high jack",
                replacements: PokerVocabulary.replacements
            ).text,
            "I am in the HJ"
        )
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "the low jack",
                replacements: PokerVocabulary.replacements
            ).text,
            "LJ"
        )
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "lojack folds",
                replacements: PokerVocabulary.replacements
            ).text,
            "LJ folds"
        )
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "low-jack calls",
                replacements: PokerVocabulary.replacements
            ).text,
            "LJ calls"
        )
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "I am in the low jack",
                replacements: PokerVocabulary.replacements
            ).text,
            "I am in the LJ"
        )
    }

    func testPokerReplacements() {
        let result = VocabularyPostProcessor.apply(
            "I open under the gun and three bet the cutoff then c-bet the flop",
            replacements: PokerVocabulary.replacements
        )
        XCTAssertTrue(result.text.contains("UTG"), result.text)
        XCTAssertTrue(result.text.contains("3-bet"), result.text)
        XCTAssertTrue(result.text.contains("CO"), result.text)
        XCTAssertTrue(result.text.contains("flop"), result.text)
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "I jam all in after a for bet",
                replacements: PokerVocabulary.replacements
            ).text,
            "I jam all-in after a 4-bet"
        )
    }

    func testUnderTheGunPlusTwoBecomesUTGPlusTwo() {
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "I open under the gun plus two",
                replacements: PokerVocabulary.replacements
            ).text,
            "I open UTG+2"
        )
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "you tee gee plus one three bet",
                replacements: PokerVocabulary.replacements
            ).text,
            "UTG+1 3-bet"
        )
        XCTAssertEqual(
            VocabularyPostProcessor.apply(
                "utg plus 2 folds",
                replacements: PokerVocabulary.replacements
            ).text,
            "UTG+2 folds"
        )
    }

    func testJackNineSuitedIsAHandNotASeat() {
        XCTAssertEqual(
            PokerHandNormalizer.apply(
                VocabularyPostProcessor.apply(
                    "I had jack nine suited",
                    replacements: PokerVocabulary.replacements
                ).text
            ),
            "I had J9"
        )
    }

    func testPokerDoesNotRewriteOrdinaryEnglish() {
        let foldTurn = VocabularyPostProcessor.apply(
            "I fold the turn and call the river",
            replacements: PokerVocabulary.replacements
        )
        XCTAssertEqual(foldTurn.text, "I fold the turn and call the river")

        let button = VocabularyPostProcessor.apply(
            "Press the button to continue",
            replacements: PokerVocabulary.replacements
        )
        XCTAssertEqual(button.text, "Press the button to continue")

        let position = VocabularyPostProcessor.apply(
            "You are in position to help",
            replacements: PokerVocabulary.replacements
        )
        XCTAssertEqual(position.text, "You are in position to help")
    }

    func testPokerHandNormalizer() {
        XCTAssertEqual(
            PokerHandNormalizer.apply("I had pocket aces"),
            "I had AA"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack nine"),
            "J9"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack nine suited"),
            "J9"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack nine clubs"),
            "J9c"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack nine of clubs"),
            "J9c"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack nine suited clubs"),
            "J9c"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack nine spades"),
            "J9s"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack nine hearts"),
            "J9h"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack nine diamonds"),
            "J9d"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack of clubs nine of hearts"),
            "Jc9h"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("nine of hearts jack of clubs"),
            "Jc9h"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("jack of clubs nine of clubs"),
            "J9c"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("ace king offsuit"),
            "AKo"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("ten five-gallon buckets"),
            "ten five-gallon buckets"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("ten five"),
            "ten five"
        )
    }

    func testLedgerSentenceStillContainsInThe() {
        let text = VocabularyLearner.shared.postProcess(
            "he's my number one guy in the ledger"
        )
        XCTAssertTrue(text.contains("in the"))
        XCTAssertFalse(text.lowercased().contains("kun chen"))
    }

    func testCommonEnglishStillBlockedAsSource() {
        XCTAssertFalse(VocabularyLearner.isValidReplacementSource("in the"))
        XCTAssertFalse(VocabularyLearner.isValidReplacementSource("the"))
        XCTAssertTrue(VocabularyLearner.isValidReplacementSource("koon chan"))
        XCTAssertTrue(VocabularyLearner.isValidReplacementSource("3-bet"))
        XCTAssertTrue(VocabularyLearner.isValidReplacementSource("UTG"))
        XCTAssertTrue(VocabularyLearner.isValidManualTerm("3BP"))
        XCTAssertTrue(VocabularyLearner.isValidManualTerm("bb/100"))
    }
}
