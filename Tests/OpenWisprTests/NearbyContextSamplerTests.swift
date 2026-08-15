import XCTest
@testable import OpenWisprLib

final class NearbyContextSamplerTests: XCTestCase {
    func testExtractsCapitalizedNamesAndSkipsCommonEnglish() {
        let names = NearbyContextSampler.extractProperNouns(
            from: "Hey Sarah, thanks for sending the proposal to Kun Chen."
        )
        XCTAssertTrue(names.contains("Sarah"))
        XCTAssertTrue(names.contains("Kun"))
        XCTAssertTrue(names.contains("Chen"))
        XCTAssertFalse(names.contains("Hey"))
        XCTAssertFalse(names.contains("the"))
    }

    func testApplyVisibleSpellingsRestoresOnScreenNames() {
        let restored = NearbyContextSampler.applyVisibleSpellings(
            "hey sarah thanks for sending it to kun chen",
            names: ["Sarah", "Kun Chen"]
        )
        XCTAssertEqual(restored, "hey Sarah thanks for sending it to Kun Chen")
    }

    func testApplyVisibleSpellingsNeverRewritesInThe() {
        let sentence = "Would it land in the real ledger as well as Laird getting a text?"
        let restored = NearbyContextSampler.applyVisibleSpellings(
            sentence,
            names: ["Sarah", "Kun"]
        )
        XCTAssertEqual(restored, sentence)
    }

    func testIgnoresCommonEnglishEvenIfPassedAsAName() {
        let restored = NearbyContextSampler.applyVisibleSpellings(
            "in the real ledger",
            names: ["In", "The"]
        )
        XCTAssertEqual(restored, "in the real ledger")
    }
}

final class TextPostProcessorStructuralTests: XCTestCase {
    func testStructuralNewLineDoesNotRewritePeriod() {
        XCTAssertEqual(
            TextPostProcessor.processStructural("wait a period of time new line next"),
            "wait a period of time \n next"
        )
    }

    func testStructuralNewParagraph() {
        XCTAssertEqual(
            TextPostProcessor.processStructural("first new paragraph second"),
            "first \n\n second"
        )
    }
}
