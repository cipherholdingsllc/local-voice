import Foundation
import XCTest
@testable import OpenWisprLib

final class ConnectIntelligenceTests: XCTestCase {
    func testDistinctiveRepeatedPhraseFormsCluster() {
        let records = [
            record("The release checklist needs stable signing verification", offset: 0),
            record("Please add stable signing verification to the Mac mini checklist", offset: 10),
        ]

        let clusters = ConnectIntelligence.clusters(from: records)

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters[0].recordIDs), Set(records.map(\.id)))
        XCTAssertTrue(clusters[0].sharedTerms.contains("stable signing verification"))
    }

    func testGenericOverlapDoesNotFormCluster() {
        let records = [
            record("Please make this work with the current application", offset: 0),
            record("I want this other feature to work for the user", offset: 10),
        ]

        XCTAssertTrue(ConnectIntelligence.clusters(from: records).isEmpty)
    }

    func testClusterIDAndOrderingAreInputIndependent() {
        let first = record("Stable signing verification must pass today", offset: 0)
        let second = record("Stable signing verification is required again", offset: 10)

        XCTAssertEqual(
            ConnectIntelligence.clusters(from: [first, second]),
            ConnectIntelligence.clusters(from: [second, first])
        )
    }

    private func record(_ text: String, offset: TimeInterval) -> LocalVoiceRecord {
        LocalVoiceRecord(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            rawText: text,
            polishedText: text,
            applicationName: "Tests",
            bundleIdentifier: "tests",
            modeName: "Default",
            engineName: "Tests",
            language: "en",
            recordingMilliseconds: 1_000,
            finishMilliseconds: 100
        )
    }
}
