import AVFoundation
import XCTest
@testable import OpenWisprLib

final class RealSpeechCrucibleTests: XCTestCase {
    func testManifestLoadsTwelveOperatorConditions() throws {
        let url = RealSpeechCrucible.defaultManifestURL(
            repoRoot: repositoryRoot()
        )
        let manifest = try RealSpeechCrucible.loadManifest(from: url)
        XCTAssertEqual(manifest.schemaVersion, "local-voice-real-speech-crucible.v1")
        XCTAssertEqual(manifest.samples.count, 12)
        let categories = Set(manifest.samples.map(\.category))
        for needed in [
            "normal", "quiet", "fast", "lazy", "mumbled",
            "disfluent", "cough", "technical", "correction", "spelling",
        ] {
            XCTAssertTrue(categories.contains(needed), "missing \(needed)")
        }
    }

    func testStagedPostProcessMatchesLivePostProcess() {
        let raw = "um hello there scratch that um goodbye"
        let learner = VocabularyLearner.shared
        let live = learner.postProcess(raw)
        let staged = learner.stagedPostProcess(raw)
        XCTAssertEqual(live, staged.finalText)
        XCTAssertEqual(staged.rawASR, raw)
        XCTAssertNotEqual(staged.afterCohesion, raw)
    }

    func testFirstLossIsRawASRWhenEngineMisses() {
        let stages = RealSpeechTextStages(
            rawASR: "send it to dallas",
            afterVocabulary: "send it to dallas",
            vocabularyCorrections: [],
            afterCohesion: "send it to dallas",
            afterNearby: "send it to dallas",
            afterPoker: "send it to dallas",
            afterFigures: "send it to dallas",
            nearbyNames: []
        )
        let dumps = RealSpeechCrucible.stageDumps(
            reference: "Send it to Andras.",
            stages: stages
        )
        XCTAssertEqual(RealSpeechCrucible.firstLossStage(dumps: dumps), "raw_asr")
        XCTAssertEqual(RealSpeechCrucible.destructiveStages(dumps: dumps), [])
    }

    func testCohesionThatRaisesWERIsMarkedDestructive() {
        let stages = RealSpeechTextStages(
            rawASR: "send it to Andras",
            afterVocabulary: "send it to Andras",
            vocabularyCorrections: [],
            afterCohesion: "send it",
            afterNearby: "send it",
            afterPoker: "send it",
            afterFigures: "send it",
            nearbyNames: []
        )
        let dumps = RealSpeechCrucible.stageDumps(
            reference: "Send it to Andras.",
            stages: stages
        )
        XCTAssertEqual(RealSpeechCrucible.firstLossStage(dumps: dumps), "cohesion")
        XCTAssertTrue(
            RealSpeechCrucible.destructiveStages(dumps: dumps).contains("cohesion")
        )
    }

    func testCriticalTokenScoreIsSubstringOnNormalizedWords() {
        let (hits, total) = RealSpeechCrucible.criticalTokenScore(
            tokens: ["CipherOS", "Dylan"],
            hypothesis: "I need to send dylan the updated cipheros brief"
        )
        XCTAssertEqual(total, 2)
        XCTAssertEqual(hits, 2)
    }

    func testCaptureProbeReadsPCMAndSpeechActivityGate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rs-probe-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSineWav(to: url, milliseconds: 400, amplitude: 0.2)
        let probe = try RealSpeechCrucible.probeCapture(url: url)
        XCTAssertGreaterThan(probe.durationMilliseconds, 300)
        XCTAssertTrue(probe.containsLikelySpeech)
        XCTAssertTrue(probe.shouldAttemptTranscription)
    }

    func testStatusListsMissingOperatorAudioWithoutInventingWER() throws {
        let manifest = try RealSpeechCrucible.loadManifest(
            from: RealSpeechCrucible.defaultManifestURL(repoRoot: repositoryRoot())
        )
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("rs-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let status = RealSpeechCrucible.status(manifest: manifest, audioRoot: empty)
        XCTAssertEqual(status.present, [])
        XCTAssertEqual(status.missing.count, 12)
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private func writeSineWav(to url: URL, milliseconds: Int, amplitude: Float) throws {
        let sampleRate: Double = 16_000
        let frames = Int(sampleRate * Double(milliseconds) / 1000.0)
        var samples = [Float](repeating: 0, count: frames)
        for index in 0..<frames {
            samples[index] = amplitude * sin(2 * Float.pi * 440 * Float(index) / Float(sampleRate))
        }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData!.pointee.update(from: src.baseAddress!, count: frames)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )
        try file.write(from: buffer)
    }
}
