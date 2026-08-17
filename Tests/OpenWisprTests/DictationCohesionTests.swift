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

    func testWaitIMeantAlsoRetractsTheValue() {
        XCTAssertEqual(
            DictationCohesion.polish(
                "The budget is forty thousand dollars wait I meant forty-five thousand dollars"
            ),
            "The budget is forty-five thousand dollars"
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
        for heard in ["eli five", "ellie five", "eli 5", "eli5"] {
            let result = VocabularyPostProcessor.apply(
                "give me an \(heard) of the PR",
                replacements: OperatorVocabulary.replacements
            )
            XCTAssertEqual(result.text, "give me an ELI5 of the PR", heard)
        }
        XCTAssertEqual(
            VocabularyLearner.shared.postProcess("ellie five"),
            "ELI5"
        )
    }

    func testChatGptMishearsBecomeChatGPT() {
        for heard in ["chat gpt", "chatgpt", "chat gee pee tee", "chat gbt", "chat gipity"] {
            let result = VocabularyPostProcessor.apply(
                "ask \(heard) to rewrite this",
                replacements: OperatorVocabulary.replacements
            )
            XCTAssertEqual(result.text, "ask ChatGPT to rewrite this", heard)
        }
    }

    func testClodBecomesClaude() {
        let result = VocabularyPostProcessor.apply(
            "ask clod to review this",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "ask Claude to review this")
        let verb = VocabularyPostProcessor.apply(
            "the cat clawed the sofa",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(verb.text, "the cat clawed the sofa")
    }

    func testCloudCodeBecomesClaudeCode() {
        for heard in ["cloud code", "clawed code", "clock code", "clod code", "cloudcode"] {
            let result = VocabularyPostProcessor.apply(
                "open \(heard) now",
                replacements: OperatorVocabulary.replacements
            )
            XCTAssertEqual(result.text, "open Claude Code now", heard)
        }
    }

    func testBareCloudDoesNotBecomeClaude() {
        let result = VocabularyPostProcessor.apply(
            "the cloud is dark over the ledger",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "the cloud is dark over the ledger")
        XCTAssertFalse(
            OperatorVocabulary.replacements.contains { $0.from.lowercased() == "cloud" }
        )
    }

    func testEndTaxBecomesENTEXS() {
        for heard in ["end tax", "en texs", "and text", "and tax"] {
            let result = VocabularyPostProcessor.apply(
                "\(heard) is our client growth system",
                replacements: OperatorVocabulary.replacements
            )
            XCTAssertEqual(result.text, "ENTEXS is our client growth system", heard)
        }
    }

    func testLocalBoysBecomesLocalVoice() {
        let result = VocabularyPostProcessor.apply(
            "dictating into local boys on my mac mini",
            replacements: OperatorVocabulary.replacements
        )
        XCTAssertEqual(result.text, "dictating into Local Voice on my mac mini")
    }

    func testGeneralModeDoesNotApplyPokerReplacements() {
        let heard = "I use a see bet on the flop"
        let general = VocabularyLearner.shared.postProcess(
            heard,
            pokerVocabularyEnabled: false
        )
        XCTAssertFalse(general.contains("c-bet"), general)
        XCTAssertTrue(general.lowercased().contains("see bet"), general)

        let poker = VocabularyLearner.shared.postProcess(
            heard,
            pokerVocabularyEnabled: true
        )
        XCTAssertTrue(poker.contains("c-bet"), poker)
    }

    func testGeneralModeSkipsPokerHandNormalizer() {
        let heard = "I had pocket aces on jack nine suited"
        let general = VocabularyLearner.shared.postProcess(
            heard,
            pokerVocabularyEnabled: false
        )
        XCTAssertTrue(general.lowercased().contains("jack nine"), general)

        let poker = VocabularyLearner.shared.postProcess(
            heard,
            pokerVocabularyEnabled: true
        )
        XCTAssertTrue(poker.contains("J9s") || poker.contains("J9"), poker)
    }

    func testPostProcessDoesNotExpandCipherToCipherLab() {
        let text = VocabularyLearner.shared.postProcess(
            "Yo Cipher",
            pokerVocabularyEnabled: false
        )
        XCTAssertEqual(text, "Yo Cipher")
        XCTAssertFalse(text.contains("Cipher Lab"), text)
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

    func testDigitAmountsWithUnits() {
        XCTAssertEqual(
            SpokenFigureNormalizer.apply("The budget is 45 thousand dollars with a 12 percent reserve"),
            "The budget is $45,000 with a 12% reserve"
        )
        XCTAssertEqual(
            SpokenFigureNormalizer.apply("I have 2 ideas in the ledger"),
            "I have 2 ideas in the ledger"
        )
        XCTAssertEqual(
            SpokenFigureNormalizer.apply("The budget is $45k"),
            "The budget is $45,000"
        )
        XCTAssertEqual(
            SpokenFigureNormalizer.apply("The budget is 45k dollars"),
            "The budget is $45,000"
        )
        XCTAssertEqual(
            SpokenFigureNormalizer.apply("about 45k tokens"),
            "about 45k tokens"
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
