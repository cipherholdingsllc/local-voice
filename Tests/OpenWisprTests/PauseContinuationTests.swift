import XCTest
@testable import OpenWisprLib

final class PauseContinuationTests: XCTestCase {
    func testGluedContinuationUsesEllipsis() {
        let out = DictationCohesion.polish(
            "Yeah, I mean if you think about itThere should be a little bit more than a little bit."
        )
        XCTAssertEqual(
            out,
            "Yeah, I mean if you think about it... there should be a little bit more than a little bit."
        )
        XCTAssertFalse(out.contains("itThere"))
        XCTAssertFalse(out.contains("\u{2014}"))
    }

    func testFalsePeriodAfterIncompleteThoughtIsNotANewSentence() {
        let out = DictationCohesion.polish(
            "Yeah, I mean if you think about it. There should be a little bit more."
        )
        XCTAssertTrue(out.contains("it... there"), out)
        XCTAssertFalse(out.contains("it. There"), out)
    }

    func testCompleteSentencePeriodIsPreserved() {
        XCTAssertEqual(
            DictationCohesion.polish("I went home. There was a cat."),
            "I went home. There was a cat."
        )
    }

    func testQuestionMarkIsNeverRewrittenAsAJoin() {
        XCTAssertEqual(
            DictationCohesion.polish("What about it? There is more."),
            "What about it? There is more."
        )
    }

    func testExclamationIsNeverRewrittenAsAJoin() {
        XCTAssertEqual(
            DictationCohesion.polish("Look at it! There it is."),
            "Look at it! There it is."
        )
    }

    func testExistingEllipsisIsNotTreatedAsATerminator() {
        let out = DictationCohesion.polish("think about it... There should be more")
        XCTAssertTrue(out.contains("it... there"), out)
        XCTAssertFalse(out.contains("it...."), out)
        XCTAssertFalse(out.contains("it... ,"), out)
    }

    func testMidSentenceCapitalAfterIncompleteGetsAComma() {
        let out = DictationCohesion.polish("I wanted to And then I stopped")
        XCTAssertTrue(out.lowercased().contains("to, and then"), out)
        XCTAssertFalse(out.contains("to And"), out)
    }

    func testContrastUsesEnDashNotEmDash() {
        let out = DictationCohesion.polish("I would rather There was another path")
        XCTAssertTrue(out.contains("\u{2013}"), out)
        XCTAssertFalse(out.contains("\u{2014}"), out)
        XCTAssertTrue(out.lowercased().contains("rather"), out)
    }

    func testRepairIsIdempotent() {
        let raw = "Yeah, I mean if you think about it. There should be more"
        let once = PauseContinuation.repair(raw)
        XCTAssertEqual(PauseContinuation.repair(once), once)
        XCTAssertEqual(DictationCohesion.polish(DictationCohesion.polish(raw)), DictationCohesion.polish(raw))
    }

    func testEmptyAndSingleWordPassThrough() {
        XCTAssertEqual(PauseContinuation.repair(""), "")
        XCTAssertEqual(PauseContinuation.repair("Cipher"), "Cipher")
    }

    func testEmDashIsRewrittenToEnDash() {
        let out = PauseContinuation.repair("alpha \u{2014} beta")
        XCTAssertEqual(out, "alpha \u{2013} beta")
    }

    func testStreamingMergeThenPolishJoinsAPause() {
        let merged = StreamingTranscriptAssembler.merge(
            existing: "Yeah I mean if you think about it",
            incoming: "There should be a little bit more"
        )
        let out = DictationCohesion.polish(merged)
        XCTAssertTrue(out.lowercased().contains("it... there") || out.lowercased().contains("it, there"), out)
        XCTAssertFalse(out.contains("itThere"), out)
    }

    func testYoCipherDoesNotGainLab() {
        XCTAssertEqual(
            VocabularyLearner.shared.postProcess(
                "Yo Cipher",
                pokerVocabularyEnabled: false
            ),
            "Yo Cipher"
        )
    }

    func testRecapitalizeDoesNotCapitalizeAfterEllipsis() {
        XCTAssertEqual(
            DictationCohesion.recapitalizeSentences("yeah, think about it... there should be more"),
            "Yeah, think about it... there should be more"
        )
    }
}
