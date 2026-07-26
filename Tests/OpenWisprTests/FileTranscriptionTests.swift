import AVFoundation
import Foundation
import XCTest
@testable import OpenWisprLib

final class FileTranscriptionTests: XCTestCase {
    func testSupportedFileTypesAreExplicitAndCaseInsensitive() {
        for name in [
            "sample.wav",
            "sample.aiff",
            "sample.caf",
            "sample.MP3",
            "sample.m4a",
            "sample.aac",
            "sample.flac",
            "sample.ogg",
            "sample.webm",
            "sample.mp4",
            "sample.mov",
            "sample.m4v",
        ] {
            XCTAssertTrue(
                AudioFileNormalizer.supports(
                    url: URL(fileURLWithPath: "/tmp/\(name)")
                ),
                name
            )
        }
        XCTAssertFalse(
            AudioFileNormalizer.supports(
                url: URL(fileURLWithPath: "/tmp/sample.exe")
            )
        )
    }

    func testInterruptedJobFailsClosedOnReload() {
        let active = makeJob(
            status: .transcribing,
            createdAt: Date()
        )
        let store = FileTranscriptionStore(
            storageURL: nil,
            jobs: [active],
            persistenceEnabled: false
        )

        XCTAssertEqual(store.jobs.first?.status, .failed)
        XCTAssertEqual(
            store.jobs.first?.errorMessage,
            "Processing was interrupted before completion. Add the file again to retry."
        )
    }

    func testFileHistoryPersistenceCanBeDisabledAtRuntime() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "local-voice-file-toggle-\(UUID().uuidString)"
            )
        let file = directory.appendingPathComponent("file-history.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileTranscriptionStore(
            storageURL: file,
            jobs: [],
            persistenceEnabled: true
        )

        store.setPersistenceEnabled(false)
        store.enqueue(
            urls: [URL(fileURLWithPath: "/tmp/unsupported.exe")]
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.jobs.first?.status, .failed)
    }

    func testCompletedFileHistoryIsBounded() {
        let jobs = (0..<5).map { offset in
            makeJob(
                id: UUID(),
                createdAt: Date().addingTimeInterval(
                    TimeInterval(-offset)
                )
            )
        }
        let store = FileTranscriptionStore(
            storageURL: nil,
            jobs: jobs,
            persistenceEnabled: false,
            maximumJobs: 3
        )

        XCTAssertEqual(store.jobs.count, 3)
        XCTAssertEqual(
            store.jobs.map(\.createdAt),
            jobs.prefix(3).map(\.createdAt)
        )
    }

    func testTextMarkdownAndJSONExports() throws {
        let job = makeJob()

        let text = try string(job: job, format: .text)
        XCTAssertEqual(text, "First segment. Second segment.\n")

        let markdown = try string(job: job, format: .markdown)
        XCTAssertTrue(markdown.contains("# Briefing.m4a"))
        XCTAssertTrue(markdown.contains("First segment. Second segment."))

        let json = try string(job: job, format: .json)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(json.utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(
            object["schemaVersion"] as? String,
            "local-voice-file-transcript.v1"
        )
        XCTAssertEqual(object["filename"] as? String, "Briefing.m4a")
        XCTAssertNil(object["sourceURL"])
        XCTAssertNil(object["sourcePath"])
    }

    func testSRTAndWebVTTExportsUseTimestampedSegments() throws {
        let job = makeJob()

        let srt = try string(job: job, format: .srt)
        XCTAssertTrue(
            srt.contains(
                "1\n00:00:00,000 --> 00:00:30,000\nFirst segment."
            )
        )
        XCTAssertTrue(
            srt.contains(
                "2\n00:00:30,000 --> 00:01:01,250\nSecond segment."
            )
        )

        let vtt = try string(job: job, format: .vtt)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n\n"))
        XCTAssertTrue(
            vtt.contains(
                "00:00:30.000 --> 00:01:01.250\nSecond segment."
            )
        )
    }

    func testCaptionTimestampSupportsHours() {
        XCTAssertEqual(
            FileTranscriptExporter.timestamp(
                3_723_045,
                webVTT: false
            ),
            "01:02:03,045"
        )
        XCTAssertEqual(
            FileTranscriptExporter.timestamp(
                3_723_045,
                webVTT: true
            ),
            "01:02:03.045"
        )
    }

    func testNormalizerProducesCanonicalBoundedWAV() throws {
        guard AudioFileNormalizer.findFFmpeg() != nil,
              AudioFileNormalizer.findFFprobe() != nil else {
            throw XCTSkip("FFmpeg is not installed")
        }
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "local-voice-file-source-\(UUID().uuidString).wav"
            )
        defer { try? FileManager.default.removeItem(at: source) }
        try writeFixtureWAV(url: source, seconds: 1)

        let batch = try AudioFileNormalizer().normalize(url: source)
        defer { batch.cleanup() }

        XCTAssertEqual(batch.chunks.count, 1)
        XCTAssertEqual(batch.durationMilliseconds, 1_000)
        let descriptor = try LocalVoiceContract.audioDescriptor(
            for: XCTUnwrap(batch.chunks.first)
        )
        XCTAssertEqual(descriptor.sampleRateHz, 16_000)
        XCTAssertEqual(descriptor.channels, 1)
        XCTAssertEqual(descriptor.encoding, "pcm_s16le")
    }

    private func makeJob(
        status: FileTranscriptionStatus = .completed,
        id: UUID = UUID(
            uuidString: "cf795e86-e75b-443b-88a4-b0c7d8fe1511"
        )!,
        createdAt: Date = Date(
            timeIntervalSince1970: 1_753_488_000
        )
    ) -> FileTranscriptionJob {
        let segments = [
            FileTranscriptSegment(
                index: 1,
                startMilliseconds: 0,
                endMilliseconds: 30_000,
                rawText: "First segment.",
                text: "First segment.",
                engineName: "parakeet",
                modelName: "parakeet-tdt-0.6b-v3",
                route: "local_process",
                inferenceMilliseconds: 100
            ),
            FileTranscriptSegment(
                index: 2,
                startMilliseconds: 30_000,
                endMilliseconds: 61_250,
                rawText: "Second segment.",
                text: "Second segment.",
                engineName: "parakeet",
                modelName: "parakeet-tdt-0.6b-v3",
                route: "local_process",
                inferenceMilliseconds: 110
            ),
        ]
        return FileTranscriptionJob(
            id: id,
            createdAt: createdAt,
            filename: "Briefing.m4a",
            fileExtension: "m4a",
            status: status,
            progress: status == .completed ? 1 : 0.5,
            durationMilliseconds: 61_250,
            transcript: "First segment. Second segment.",
            engineSummary: "Parakeet",
            routeSummary: "Local process",
            segments: segments
        )
    }

    private func string(
        job: FileTranscriptionJob,
        format: FileTranscriptFormat
    ) throws -> String {
        let data = try FileTranscriptExporter.data(
            job: job,
            format: format
        )
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func writeFixtureWAV(
        url: URL,
        seconds: Double
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings
        )
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: frames
            )
        )
        buffer.frameLength = frames
        try file.write(from: buffer)
    }
}
