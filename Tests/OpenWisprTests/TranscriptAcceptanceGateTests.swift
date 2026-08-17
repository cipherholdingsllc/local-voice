import XCTest
@testable import OpenWisprLib

final class TranscriptAcceptanceGateTests: XCTestCase {
    private let metrics = AudioCaptureMetrics(
        totalFrames: 16_000,
        activeFrames: 9_000,
        peakAmplitude: 0.06,
        sampleRate: 16_000
    )

    func testRejectsSingleHallucinationProneWord() {
        XCTAssertFalse(
            TranscriptAcceptanceGate.shouldAccept(
                raw: "you",
                polished: "you",
                recordingMilliseconds: 900,
                captureMetrics: metrics
            )
        )
    }

    func testAcceptsCommonSingleWord() {
        XCTAssertTrue(
            TranscriptAcceptanceGate.shouldAccept(
                raw: "hello",
                polished: "hello",
                recordingMilliseconds: 900,
                captureMetrics: metrics
            )
        )
    }

    func testAcceptsMultiWordPhraseContainingYou() {
        XCTAssertTrue(
            TranscriptAcceptanceGate.shouldAccept(
                raw: "you know let's go",
                polished: "you know let's go",
                recordingMilliseconds: 900,
                captureMetrics: metrics
            )
        )
    }

    func testRejectsEmptyTranscript() {
        XCTAssertFalse(
            TranscriptAcceptanceGate.shouldAccept(
                raw: "",
                polished: "",
                recordingMilliseconds: 900,
                captureMetrics: metrics
            )
        )
    }
}
