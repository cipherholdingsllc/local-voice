import XCTest
@testable import OpenWisprLib

final class SpeechActivityAccumulatorTests: XCTestCase {
    func testSilenceDoesNotReachTranscription() {
        var accumulator = SpeechActivityAccumulator()
        accumulator.observe(Array(repeating: 0, count: 8_000))
        XCTAssertFalse(accumulator.metrics.containsLikelySpeech)
    }

    func testLowLevelInputNoiseDoesNotReachTranscription() {
        var accumulator = SpeechActivityAccumulator()
        accumulator.observe(
            (0..<8_000).map { $0.isMultiple(of: 2) ? 0.002 : -0.002 }
        )
        XCTAssertFalse(accumulator.metrics.containsLikelySpeech)
    }

    func testQuietSpeechLikeSignalReachesTranscription() {
        var accumulator = SpeechActivityAccumulator()
        let samples = (0..<4_000).map { index in
            Float(sin(Double(index) * 2 * .pi * 180 / 16_000)) * 0.018
        }
        accumulator.observe(samples)
        XCTAssertTrue(accumulator.metrics.containsLikelySpeech)
    }

    func testBriefClickDoesNotCountAsSpeech() {
        var accumulator = SpeechActivityAccumulator()
        var samples = Array(repeating: Float(0), count: 1_600)
        samples[100] = 0.5
        accumulator.observe(samples)
        XCTAssertTrue(accumulator.metrics.containsLikelySpeech)
        XCTAssertFalse(accumulator.metrics.shouldAttemptTranscription)
    }

    func testLongQuietCaptureStillAttemptsTranscription() {
        var accumulator = SpeechActivityAccumulator()
        accumulator.observe(
            (0..<8_000).map { $0.isMultiple(of: 2) ? 0.002 : -0.002 }
        )
        XCTAssertFalse(accumulator.metrics.containsLikelySpeech)
        XCTAssertTrue(accumulator.metrics.shouldAttemptTranscription)
    }
}
