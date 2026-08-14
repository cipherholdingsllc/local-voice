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
        // NOTE: does not assert a "Term1" prefix. `VocabularyLearner.shared`
        // is a real, file-backed singleton (this device's actual dictionary
        // at ~/.config/local-voice/learned-vocabulary.json); user-added
        // manual terms now intentionally lead the prompt ahead of config
        // seed terms (see `merged`), so whatever this device has already
        // learned may legitimately appear before "Term1".
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
        XCTAssertEqual(result.text, "I spoke with Kun yesterday")
    }

    func testFuzzyBoostFixesCloseToken() {
        let result = VocabularyPostProcessor.apply(
            "email kunch please",
            replacements: [],
            boostTerms: ["Kun Chen"]
        )
        XCTAssertEqual(result.text, "email Kun Chen please")
    }

    func testPhraseReplacementIsCaseInsensitive() {
        let rules = [VocabularyPostProcessor.Replacement(from: "cipher os", to: "CipherOS")]
        let result = VocabularyPostProcessor.apply(
            "use cipher os daily",
            replacements: rules
        )
        XCTAssertEqual(result.text, "use CipherOS daily")
    }

    /// The realistic failure mode: Whisper-style STT keeps word boundaries,
    /// so a two-word name almost always comes out as two separate
    /// mis-transcribed tokens, not one glued token. Before the phrase-window
    /// matcher this could never be corrected because `closestToken` only
    /// ever compared a single transcript token against the whole target.
    func testFuzzyBoostFixesTwoSeparateMishearWords() {
        let result = VocabularyPostProcessor.apply(
            "email Kuhn Chan please",
            replacements: [],
            boostTerms: ["Kun Chen"]
        )
        XCTAssertEqual(result.text, "email Kun Chen please")
    }

    func testFuzzyBoostDoesNotTouchUnrelatedWords() {
        let result = VocabularyPostProcessor.apply(
            "the sun is out today",
            replacements: [],
            boostTerms: ["Kun Chen"]
        )
        XCTAssertEqual(result.text, "the sun is out today")
    }

    func testFuzzyBoostReportsAppliedCorrectionForPromotion() {
        let result = VocabularyPostProcessor.apply(
            "email Kuhn Chan please",
            replacements: [],
            boostTerms: ["Kun Chen"]
        )
        XCTAssertEqual(result.corrections, [
            VocabularyPostProcessor.AppliedCorrection(heard: "Kuhn Chan", term: "Kun Chen"),
        ])
    }
}
