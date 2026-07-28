import AVFoundation
import XCTest
@testable import OpenWisprLib

final class DictationLatencyTests: XCTestCase {
    func testStreamingChunkerEmitsOnlyNewAudioPlusSmallOverlap() {
        var chunker = StreamingAudioChunker(
            sampleRate: 16_000,
            chunkSeconds: 2,
            overlapSeconds: 0.25
        )
        let first = chunker.append(
            Array(repeating: 0, count: 32_000)
        )
        let second = chunker.append(
            Array(repeating: 0, count: 32_000)
        )

        XCTAssertEqual(first.map(\.count), [32_000])
        XCTAssertEqual(second.map(\.count), [36_000])
    }

    func testTwoMinutePreviewWorkloadStaysLinear() {
        let sampleRate = 16_000.0
        var chunker = StreamingAudioChunker(
            sampleRate: sampleRate,
            chunkSeconds: 2,
            overlapSeconds: 0.25
        )
        var scheduledFrames = 0

        for _ in 0..<60 {
            let chunks = chunker.append(
                Array(repeating: 0, count: 32_000)
            )
            scheduledFrames += chunks.reduce(0) {
                $0 + $1.count
            }
        }

        let scheduledSeconds = Double(scheduledFrames) / sampleRate
        XCTAssertLessThanOrEqual(scheduledSeconds, 135)
        XCTAssertGreaterThan(scheduledSeconds, 120)
    }

    func testStreamingChunkerWaitsForACompleteInterval() {
        var chunker = StreamingAudioChunker(
            sampleRate: 16_000,
            chunkSeconds: 2,
            overlapSeconds: 0.25
        )
        XCTAssertTrue(
            chunker.append(
                Array(repeating: 0, count: 31_999)
            ).isEmpty
        )
        XCTAssertEqual(chunker.append([0]).map(\.count), [32_000])
    }

    func testIncrementalWriterProducesStandalonePCMChunk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "local-voice-streaming-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let chunkURL = directory.appendingPathComponent("chunk.wav")
        try StreamingChunkWriter.write(
            samples: Array(repeating: 0, count: 36_000),
            sampleRate: 16_000,
            destinationURL: chunkURL
        )
        XCTAssertEqual(
            try AVAudioFile(forReading: chunkURL).length,
            36_000
        )
    }

    func testStreamingAssemblerRemovesBoundaryOverlap() {
        XCTAssertEqual(
            StreamingTranscriptAssembler.merge(
                existing: "The river keeps moving",
                incoming: "keeps moving through the city."
            ),
            "The river keeps moving through the city."
        )
    }

    func testStreamingAssemblerAcceptsNewCumulativeReplacement() {
        XCTAssertEqual(
            StreamingTranscriptAssembler.merge(
                existing: "A complete thought.",
                incoming: "A complete thought. Then another."
            ),
            "A complete thought. Then another."
        )
    }

    func testEndedStreamingSessionRejectsStaleWork() {
        let gate = StreamingSessionGate()
        let requestID = UUID()

        gate.begin(requestID)
        XCTAssertTrue(gate.isActive(requestID))
        gate.end(requestID)
        XCTAssertFalse(gate.isActive(requestID))
    }

    func testObservedTwoMinuteCaseUsesFastLongFormRoute() {
        XCTAssertEqual(
            DictationCleanupPolicy.route(
                enabled: true,
                characterCount: 1_407,
                recordingMilliseconds: 119_300
            ),
            .fastLongForm
        )
    }

    func testShortMessageKeepsLocalRefinement() {
        XCTAssertEqual(
            DictationCleanupPolicy.route(
                enabled: true,
                characterCount: 164,
                recordingMilliseconds: 10_900
            ),
            .synchronousOllama
        )
    }

    func testDisabledRefinementNeverCallsOllama() {
        XCTAssertEqual(
            DictationCleanupPolicy.route(
                enabled: false,
                characterCount: 1_407,
                recordingMilliseconds: 119_300
            ),
            .disabled
        )
    }

}
