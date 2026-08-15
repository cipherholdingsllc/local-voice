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

    func testPokerReplacements() {
        let result = VocabularyPostProcessor.apply(
            "I open under the gun and three bet the cutoff then c-bet the flop",
            replacements: PokerVocabulary.replacements
        )
        XCTAssertTrue(result.text.contains("UTG"), result.text)
        XCTAssertTrue(result.text.contains("3-bet"), result.text)
        XCTAssertTrue(result.text.contains("CO"), result.text)
        XCTAssertTrue(result.text.contains("flop"), result.text)
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
            PokerHandNormalizer.apply("jack nine suited"),
            "J9s"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("ace king offsuit"),
            "AKo"
        )
        XCTAssertEqual(
            PokerHandNormalizer.apply("ten five-gallon buckets"),
            "ten five-gallon buckets"
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
