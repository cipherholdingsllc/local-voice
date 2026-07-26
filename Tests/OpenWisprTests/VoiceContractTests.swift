import AVFoundation
import Foundation
import XCTest
@testable import OpenWisprLib

final class VoiceContractTests: XCTestCase {
    func testAudioDescriptorReadsCanonicalRecorderFormat() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "local-voice-contract-\(UUID().uuidString).wav"
            )
        defer { try? FileManager.default.removeItem(at: url) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            let buffer = try XCTUnwrap(
                AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: 1_600
                )
            )
            buffer.frameLength = 1_600
            try file.write(from: buffer)
        }

        let descriptor = try LocalVoiceContract.audioDescriptor(for: url)
        XCTAssertEqual(descriptor.sampleRateHz, 16_000)
        XCTAssertEqual(descriptor.channels, 1)
        XCTAssertEqual(descriptor.durationMs, 100)
        XCTAssertGreaterThanOrEqual(descriptor.byteLength, 44)
    }

    func testSamplePairUsesCanonicalVersionsAndProductBoundary() throws {
        let pair = try LocalVoiceContract.samplePair()

        XCTAssertEqual(pair.request.schemaVersion, "voice-request.v1")
        XCTAssertEqual(pair.response.schemaVersion, "voice-response.v1")
        XCTAssertEqual(pair.request.requestId, pair.response.requestId)
        XCTAssertEqual(pair.request.profileId, .generalDefault)
        XCTAssertEqual(pair.response.profileId, .generalDefault)
        XCTAssertEqual(pair.request.origin, .localVoiceMacOS)
        XCTAssertEqual(pair.response.origin, .localVoiceMacOS)
        XCTAssertEqual(pair.response.engine.route, .localProcess)
        XCTAssertEqual(pair.response.privacy.route, .localProcess)
        XCTAssertEqual(pair.response.privacy.networkEgress, .none)
        XCTAssertFalse(pair.response.privacy.audioRetained)
    }

    func testRequiredNullableFieldsEncodeAsExplicitNull() throws {
        let pair = try LocalVoiceContract.makePair(
            requestId: UUID(),
            profileId: .generalDefault,
            audio: VoiceContractAudio(byteLength: 32_044, durationMs: 1_000),
            requestedLanguage: "auto",
            detectedLanguage: nil,
            enginePreference: .whisper,
            configuredModel: nil,
            keepWarm: true,
            promptVocabulary: [],
            maximumDurationMilliseconds: 60_000,
            rawTranscript: nil,
            normalizedTranscript: "Local contract.",
            engineName: "whisper-server",
            engineModel: nil,
            engineRoute: .localLoopback,
            enginePersistent: true,
            inferenceMilliseconds: 20,
            finishMilliseconds: 5,
            transcriptRetention: .localHistory
        )

        let data = try JSONEncoder().encode(pair)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let request = try XCTUnwrap(object["request"] as? [String: Any])
        let enginePolicy = try XCTUnwrap(
            request["enginePolicy"] as? [String: Any]
        )
        let response = try XCTUnwrap(object["response"] as? [String: Any])
        let transcript = try XCTUnwrap(
            response["transcript"] as? [String: Any]
        )
        let engine = try XCTUnwrap(response["engine"] as? [String: Any])
        let language = try XCTUnwrap(
            response["language"] as? [String: Any]
        )
        let privacy = try XCTUnwrap(
            response["privacy"] as? [String: Any]
        )

        XCTAssertTrue(enginePolicy["model"] is NSNull)
        XCTAssertTrue(transcript["raw"] is NSNull)
        XCTAssertTrue(engine["model"] is NSNull)
        XCTAssertTrue(language["detected"] is NSNull)
        XCTAssertEqual(privacy["networkEgress"] as? String, "loopback_only")
    }

    func testLocalVoiceCannotEmitPokerProfile() {
        XCTAssertThrowsError(
            try LocalVoiceContract.makePair(
                requestId: UUID(),
                profileId: .pokerExploit,
                audio: VoiceContractAudio(
                    byteLength: 32_044,
                    durationMs: 1_000
                ),
                requestedLanguage: "en",
                detectedLanguage: "en",
                enginePreference: .whisper,
                configuredModel: "base.en",
                keepWarm: true,
                promptVocabulary: [],
                maximumDurationMilliseconds: 60_000,
                rawTranscript: "fold",
                normalizedTranscript: "Fold.",
                engineName: "whisper-server",
                engineModel: "base.en",
                engineRoute: .localLoopback,
                enginePersistent: true,
                inferenceMilliseconds: 20,
                finishMilliseconds: 5,
                transcriptRetention: .localSession
            )
        )
    }

    func testProfileMappingKeepsGeneralAndPokerSurfacesIsolated() {
        XCTAssertEqual(
            VoiceContractProfileID.localVoiceProfile(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                modeName: nil
            ),
            .generalMessage
        )
        XCTAssertEqual(
            VoiceContractProfileID.localVoiceProfile(
                bundleIdentifier: "com.openai.codex",
                modeName: nil
            ),
            .generalTechnical
        )
        XCTAssertEqual(
            VoiceContractProfileID.localVoiceProfile(
                bundleIdentifier: "com.apple.Terminal",
                modeName: nil
            ),
            .generalCommand
        )
        XCTAssertTrue(
            VoiceContractProfileID.allCases
                .filter(\.isGeneral)
                .allSatisfy { $0 != .pokerExploit }
        )
    }

    func testVocabularyIsBoundedAndDeduplicated() throws {
        let values = Array(repeating: "CipherOS", count: 10)
            + (0..<300).map { "term-\($0)-" + String(repeating: "x", count: 150) }
        let pair = try LocalVoiceContract.makePair(
            requestId: UUID(),
            profileId: .generalTechnical,
            audio: VoiceContractAudio(byteLength: 32_044, durationMs: 1_000),
            requestedLanguage: "en",
            detectedLanguage: "en",
            enginePreference: .auto,
            configuredModel: "base.en",
            keepWarm: true,
            promptVocabulary: values,
            maximumDurationMilliseconds: 60_000,
            rawTranscript: "test",
            normalizedTranscript: "Test.",
            engineName: "parakeet",
            engineModel: "parakeet-tdt-0.6b-v3",
            engineRoute: .localProcess,
            enginePersistent: true,
            inferenceMilliseconds: 20,
            finishMilliseconds: 5,
            transcriptRetention: .localHistory
        )

        XCTAssertEqual(pair.request.promptVocabulary.count, 256)
        XCTAssertEqual(
            Set(pair.request.promptVocabulary).count,
            pair.request.promptVocabulary.count
        )
        XCTAssertTrue(
            pair.request.promptVocabulary.allSatisfy {
                !$0.isEmpty && $0.count <= 128
            }
        )
    }

    func testGeneralProfilesMatchTenMinuteRuntimeCap() {
        XCTAssertEqual(
            VoiceContractProfileID.generalDefault
                .maximumDurationMilliseconds,
            600_000
        )
        XCTAssertEqual(
            VoiceContractProfileID.generalCommand
                .maximumDurationMilliseconds,
            120_000
        )
    }
}
