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

    func testPromptStringIsDisabledToAvoidWhisperBias() {
        let prompt = VocabularyLearner.shared.promptString(
            configTerms: ["OGrE", "Kun", "CipherOS"],
            maxCharacters: 224
        )
        XCTAssertEqual(prompt, "")
    }

    func testCommonEnglishIsNotCorruptedByDictionary() {
        let rules = VocabularyLearner.shared.replacementRules()
        let result = VocabularyPostProcessor.apply(
            "What are you talking about man",
            replacements: rules
        )
        XCTAssertEqual(result.text, "What are you talking about man")
    }

    func testInTheReplacementSourceIsRejected() {
        XCTAssertFalse(VocabularyLearner.isValidReplacementSource("in the"))
        XCTAssertFalse(VocabularyLearner.isValidReplacementSource("of the"))
        XCTAssertTrue(VocabularyLearner.isValidReplacementSource("koon chan"))
    }

    func testSeededReplacementRefreshesStaleTarget() {
        let stale = [
            VocabularyPostProcessor.Replacement(from: "get hubs", to: "get hubs repo"),
        ]
        let refreshed = VocabularyLearner.refreshedReplacements(existing: stale)
        let github = refreshed.first {
            $0.from.caseInsensitiveCompare("get hubs") == .orderedSame
        }
        XCTAssertEqual(github?.to, "GitHub")
        XCTAssertEqual(github?.origin, .seeded)
    }

    func testUserReplacementIsNotClobberedBySeed() {
        let taught = [
            VocabularyPostProcessor.Replacement(
                from: "get hubs",
                to: "get hubs repo",
                origin: .user
            ),
        ]
        let refreshed = VocabularyLearner.refreshedReplacements(existing: taught)
        let github = refreshed.first {
            $0.from.caseInsensitiveCompare("get hubs") == .orderedSame
        }
        XCTAssertEqual(github?.to, "get hubs repo")
        XCTAssertEqual(github?.origin, .user)
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

    func testFuzzyBoostFixesKoonChan() {
        let result = VocabularyPostProcessor.apply(
            "Testing, testing one, two, three. Koon Chan.",
            replacements: [],
            boostTerms: ["Kun Chen"]
        )
        XCTAssertEqual(result.text, "Testing, testing one, two, three. Kun Chen.")
        XCTAssertEqual(result.corrections.first?.heard, "Koon Chan")
    }

    func testSingleWordFuzzyBoostSkipsCommonEnglishTokens() {
        let result = VocabularyPostProcessor.apply(
            "What are you talking about man",
            replacements: [],
            boostTerms: ["Kun"]
        )
        XCTAssertEqual(
            result.text,
            "What are you talking about man",
            "Common English tokens must never be fuzzy-corrected"
        )
    }

    func testMultiWordBoostLeavesCommonEnglishUntouched() {
        let result = VocabularyPostProcessor.apply(
            "What are you talking about man",
            replacements: [],
            boostTerms: ["Kun Chen"]
        )
        XCTAssertEqual(result.text, "What are you talking about man")
    }

    func testInTheIsNeverReplacedByKunChen() {
        let toxic = [
            VocabularyPostProcessor.Replacement(from: "in the", to: "Kun Chen"),
        ]
        let withRule = VocabularyPostProcessor.apply(
            "Would it land in the real ledger as well as Laird getting a text?",
            replacements: toxic
        )
        XCTAssertEqual(
            withRule.text,
            "Would it land Kun Chen real ledger as well as Laird getting a text?",
            "Documents the toxic rule shape we must never persist"
        )

        let safe = VocabularyPostProcessor.apply(
            "Would it land in the real ledger as well as Laird getting a text?",
            replacements: [],
            boostTerms: ["Kun Chen"]
        )
        XCTAssertEqual(
            safe.text,
            "Would it land in the real ledger as well as Laird getting a text?"
        )
    }

    func testFuzzyBoostDoesNotPromoteInThe() {
        let result = VocabularyPostProcessor.apply(
            "Would it land in the real ledger",
            replacements: [],
            boostTerms: ["Kun Chen"]
        )
        XCTAssertTrue(result.corrections.isEmpty)
        XCTAssertEqual(result.text, "Would it land in the real ledger")
    }

    func testFuzzyBoostDoesNotExpandPartialMultiWordMatch() {
        let result = VocabularyPostProcessor.apply(
            "Yo Cipher",
            replacements: [],
            boostTerms: ["Cipher Lab"]
        )
        XCTAssertEqual(result.text, "Yo Cipher")
        XCTAssertTrue(result.corrections.isEmpty)
    }
}
