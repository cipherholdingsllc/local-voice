import XCTest
@testable import OpenWisprLib

final class VoiceBenchmarkTests: XCTestCase {
    func testTokenNormalizationIsCaseAndPunctuationInsensitive() {
        XCTAssertEqual(
            VoiceBenchmark.tokens("Three-bet, CIPHER_OS!"),
            ["three", "bet", "cipher", "os"]
        )
    }

    func testEditDistanceCountsInsertionsDeletionsAndSubstitutions() {
        XCTAssertEqual(
            VoiceBenchmark.editDistance(
                ["local", "voice", "is", "ready"],
                ["local", "speech", "ready"]
            ),
            2
        )
    }

    func testPercentileUsesNearestRank() {
        let values = [500.0, 100.0, 400.0, 200.0, 300.0]
        XCTAssertEqual(
            VoiceBenchmark.percentile(values, fraction: 0.50),
            300
        )
        XCTAssertEqual(
            VoiceBenchmark.percentile(values, fraction: 0.95),
            500
        )
    }
}
