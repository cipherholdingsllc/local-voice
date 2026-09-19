import XCTest
@testable import OpenWisprLib

final class InferenceTimeoutTests: XCTestCase {
    func testShortTakesKeepTheHistoricTwoMinuteFloor() {
        // Floor is max(120, duration×2.5+90). It still binds just above the
        // ≤8s chunk path, where scaled timeout is still under 120s.
        XCTAssertEqual(InferenceTimeout.httpSeconds(durationSeconds: 10), 120)
        XCTAssertEqual(InferenceTimeout.httpSeconds(durationSeconds: 12), 120)
    }

    func testSpokenTakesScaleAboveTheFloor() {
        XCTAssertEqual(
            InferenceTimeout.httpSeconds(durationSeconds: 30),
            30 * InferenceTimeout.realtimeFactor + InferenceTimeout.overheadSeconds
        )
        XCTAssertEqual(
            InferenceTimeout.httpSeconds(durationSeconds: 88),
            88 * InferenceTimeout.realtimeFactor + InferenceTimeout.overheadSeconds
        )
    }

    func testMultiMinuteTakesScalePastTwoMinutes() {
        let threeMinutes = InferenceTimeout.httpSeconds(durationSeconds: 180)
        XCTAssertGreaterThan(threeMinutes, 120)
        XCTAssertEqual(threeMinutes, 180 * 2.5 + 90)
        let fiveMinutes = InferenceTimeout.httpSeconds(durationSeconds: 300)
        XCTAssertGreaterThan(fiveMinutes, threeMinutes)
        XCTAssertLessThanOrEqual(fiveMinutes, InferenceTimeout.maximumSeconds)
    }

    func testChunksUseATightCeilingSoTheyCannotStarveFinalize() {
        let chunk = InferenceTimeout.httpSeconds(durationSeconds: 2, isChunk: true)
        XCTAssertLessThanOrEqual(chunk, InferenceTimeout.chunkMaximumSeconds)
        XCTAssertGreaterThanOrEqual(chunk, 15)
    }

    func testCLIBudgetIsAtLeastAsGenerousAsHTTP() {
        let duration: TimeInterval = 240
        XCTAssertGreaterThanOrEqual(
            InferenceTimeout.cliSeconds(durationSeconds: duration),
            InferenceTimeout.httpSeconds(durationSeconds: duration)
        )
    }

    func testEmptyTranscriptRecoveryOnlyForLongTakes() {
        XCTAssertTrue(
            InferenceTimeout.shouldRecoverFromEmptyTranscript(
                recordingMilliseconds: 180_000
            )
        )
        XCTAssertFalse(
            InferenceTimeout.shouldRecoverFromEmptyTranscript(
                recordingMilliseconds: 88_000
            )
        )
        XCTAssertTrue(InferenceTimeout.isTimeout(WhisperServerError.timeout))
        XCTAssertTrue(InferenceTimeout.isTimeout(TranscriberError.timeout))
        XCTAssertTrue(InferenceTimeout.isTimeout(ParakeetError.timeout))
        XCTAssertFalse(InferenceTimeout.isTimeout(WhisperServerError.emptyResponse))
    }

    func testWAVHeaderDuration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("timeout-header-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: Swift.withUnsafeBytes(of: UInt32(36).littleEndian) { Data($0) })
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.append(contentsOf: Swift.withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(contentsOf: Swift.withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        data.append(contentsOf: Swift.withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        data.append(contentsOf: Swift.withUnsafeBytes(of: UInt32(16_000).littleEndian) { Data($0) })
        data.append(contentsOf: Swift.withUnsafeBytes(of: UInt32(32_000).littleEndian) { Data($0) })
        data.append(contentsOf: Swift.withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })
        data.append(contentsOf: Swift.withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) })
        data.append(contentsOf: "data".utf8)
        let dataSize: UInt32 = 16_000 * 2 * 180
        data.append(contentsOf: Swift.withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        try data.write(to: url)
        let duration = InferenceTimeout.wavDurationFromHeader(url: url)
        XCTAssertEqual(duration ?? 0, 180, accuracy: 0.01)
        // Header-only fixtures may look empty to AVAudioFile, so budget from
        // the parsed duration — the relationship this test owns.
        let http = InferenceTimeout.httpSeconds(durationSeconds: duration ?? 0)
        XCTAssertEqual(
            http,
            180 * InferenceTimeout.realtimeFactor + InferenceTimeout.overheadSeconds
        )
        XCTAssertGreaterThan(http, InferenceTimeout.minimumSeconds)
    }
}

final class LockGesturePolicyTests: XCTestCase {
    func testCommandPlusFnEngagesLock() {
        XCTAssertTrue(
            LockGesturePolicy.shouldEngageExplicitLock(
                activationMode: .holdAndDoubleTapLock,
                alreadyLocked: false,
                commandDown: true,
                fnJustPressed: true
            )
        )
    }

    func testCommandDuringHoldDoesNotLock() {
        XCTAssertFalse(
            LockGesturePolicy.shouldEngageExplicitLock(
                activationMode: .holdAndDoubleTapLock,
                alreadyLocked: false,
                commandDown: true,
                fnJustPressed: false
            )
        )
    }

    func testPlainFnDownDoesNotLock() {
        XCTAssertFalse(
            LockGesturePolicy.shouldEngageExplicitLock(
                activationMode: .holdAndDoubleTapLock,
                alreadyLocked: false,
                commandDown: false,
                fnJustPressed: true
            )
        )
    }

    func testLockedSessionPastesInsteadOfLiveAX() {
        XCTAssertFalse(
            LockedDictationFinalization.shouldCommitViaLiveComposer(
                wasLockSession: true,
                hasLiveInsertion: true
            )
        )
        XCTAssertTrue(
            LockedDictationFinalization.shouldCommitViaLiveComposer(
                wasLockSession: false,
                hasLiveInsertion: true
            )
        )
    }
}
