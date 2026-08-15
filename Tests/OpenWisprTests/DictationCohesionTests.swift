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

    func testWaitIMeanKeepsTheSentenceFrame() {
        XCTAssertEqual(
            DictationCohesion.polish(
                "The budget is forty thousand dollars wait, I mean forty-five thousand dollars with a twelve percent reserve"
            ),
            "The budget is forty-five thousand dollars with a twelve percent reserve"
        )
    }

    func testInTheSurvivesCohesion() {
        let sentence =
            "Would it land in the real ledger as well as Laird getting a text?"
        XCTAssertEqual(DictationCohesion.polish(sentence), sentence)
    }

    func testCollapsesStutteredRepeats() {
        XCTAssertEqual(
            DictationCohesion.polish("our, our, our GitHub"),
            "Our GitHub"
        )
        XCTAssertEqual(
            DictationCohesion.polish("the the give me the final delivery"),
            "The give me the final delivery"
        )
    }

    func testFormatsSpokenNumberedListsWhenTwoMarkersPresent() {
        let polished = DictationCohesion.polish("number one buy milk number two call Kun")
        XCTAssertTrue(polished.contains("1."))
        XCTAssertTrue(polished.contains("2."))
        XCTAssertFalse(polished.lowercased().contains("number one"))
        XCTAssertTrue(polished.lowercased().contains("buy milk"))
        XCTAssertTrue(polished.contains("Kun"))
    }

    func testLeavesNumberOneAloneWithoutASecondMarker() {
        XCTAssertEqual(
            DictationCohesion.polish("he's my number one guy"),
            "He's my number one guy"
        )
    }

    func testFormatsSpokenBulletsWhenTwoMarkersPresent() {
        let polished = DictationCohesion.polish("bullet milk bullet eggs")
        XCTAssertTrue(polished.contains("- "))
        XCTAssertTrue(polished.contains("milk"))
        XCTAssertTrue(polished.contains("eggs"))
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
            "smelt these get-hubs",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "smelt these GitHub")
    }

    func testKunchanBecomesKunChen() {
        let result = VocabularyPostProcessor.apply(
            "the same way as Kunchan",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "the same way as Kun Chen")
    }

    func testAtomicVaultBecomesAutomicVault() {
        let result = VocabularyPostProcessor.apply(
            "open the atomic vault app",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "open the Automic Vault app")
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

    func testEliFiveBecomesELI5() {
        let result = VocabularyPostProcessor.apply(
            "give me an eli five of the PR",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "give me an ELI5 of the PR")
    }
}

final class SpokenFigureNormalizerTests: XCTestCase {
    func testMoneyAndPercent() {
        XCTAssertEqual(
            SpokenFigureNormalizer.apply(
                "The budget is forty-five thousand dollars with a twelve percent reserve"
            ),
            "The budget is $45,000 with a 12% reserve"
        )
    }

    func testMillisecondsAndPort() {
        XCTAssertEqual(
            SpokenFigureNormalizer.apply(
                "retries after a five hundred millisecond timeout on port four three eight seven"
            ),
            "retries after a 500ms timeout on port 4387"
        )
    }

    func testLeavesOrdinaryCountsAlone() {
        XCTAssertEqual(
            SpokenFigureNormalizer.apply("I have two ideas in the ledger"),
            "I have two ideas in the ledger"
        )
    }

    func testPostProcessBudgetCorrection() {
        let text = VocabularyLearner.shared.postProcess(
            "The budget is forty thousand dollars wait, I mean forty-five thousand dollars with a twelve percent reserve"
        )
        XCTAssertTrue(text.contains("$45,000"), text)
        XCTAssertTrue(text.contains("12%"), text)
        XCTAssertFalse(text.contains("forty thousand"), text)
        XCTAssertTrue(text.contains("in the") || !text.lowercased().contains("kun chen"))
    }
}
