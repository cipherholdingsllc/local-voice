import XCTest
@testable import OpenWisprLib

final class VocabularyLearnerTests: XCTestCase {
    func testManualTermAllowsSingleCharacterNames() {
        XCTAssertTrue(VocabularyLearner.isValidManualTerm("K"))
        XCTAssertTrue(VocabularyLearner.isValidManualTerm("Kun Chen"))
    }

    func testAutoLearnedRejectsGarbage() {
        XCTAssertFalse(VocabularyLearner.isValidAutoLearnedTerm("000"))
        XCTAssertFalse(VocabularyLearner.isValidAutoLearnedTerm("2488DA72"))
        XCTAssertTrue(VocabularyLearner.isValidAutoLearnedTerm("Kun"))
    }

    func testPromptStringIsBounded() {
        let learner = VocabularyLearner.shared
        let terms = (1...50).map { "Term\($0)" }
        let prompt = learner.promptString(configTerms: terms, maxCharacters: 40)
        XCTAssertLessThanOrEqual(prompt.count, 40)
        XCTAssertTrue(prompt.hasPrefix("Term1"))
    }
}

final class VocabularyPostProcessorTests: XCTestCase {
    func testReplacementRuleFixesMisspelling() {
        let rules = [VocabularyPostProcessor.Replacement(from: "coon", to: "Kun")]
        let result = VocabularyPostProcessor.apply(
            "I spoke with coon yesterday",
            replacements: rules,
            boostTerms: ["Kun"]
        )
        XCTAssertEqual(result, "I spoke with Kun yesterday")
    }

    func testFuzzyBoostFixesCloseToken() {
        let result = VocabularyPostProcessor.apply(
            "email kunch please",
            replacements: [],
            boostTerms: ["Kun Chen"]
        )
        XCTAssertEqual(result, "email Kun Chen please")
    }

    func testPhraseReplacementIsCaseInsensitive() {
        let rules = [VocabularyPostProcessor.Replacement(from: "cipher os", to: "CipherOS")]
        let result = VocabularyPostProcessor.apply(
            "use cipher os daily",
            replacements: rules
        )
        XCTAssertEqual(result, "use CipherOS daily")
    }
}
