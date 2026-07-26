import Foundation
import XCTest
@testable import OpenWisprLib

final class LocalVoiceStoreTests: XCTestCase {
    func testTodayMetricsUsePersistedRecordData() {
        let records = [
            makeRecord(text: "one two three", recordingMs: 30_000, finishMs: 400),
            makeRecord(text: "four five", recordingMs: 15_000, finishMs: 600),
        ]
        let store = LocalVoiceStore(
            storageURL: nil,
            records: records,
            retentionDays: 30
        )

        XCTAssertEqual(store.todayWordCount, 5)
        XCTAssertEqual(store.todayRecords.count, 2)
        XCTAssertEqual(store.todayVoiceMinutes, 0.75, accuracy: 0.001)
        XCTAssertEqual(store.medianFinishMilliseconds, 500)
    }

    func testAppendPersistsAndReloadsHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-voice-store-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = makeRecord(text: "A local transcript")
        let writer = LocalVoiceStore(
            storageURL: file,
            records: [],
            retentionDays: 30,
            persistenceEnabled: true
        )
        writer.append(original)

        let reader = LocalVoiceStore(
            storageURL: file,
            retentionDays: 30,
            persistenceEnabled: true
        )
        XCTAssertEqual(reader.records, [original])
    }

    func testMaximumRecordCountDropsOldest() {
        let store = LocalVoiceStore(
            storageURL: nil,
            records: [],
            maximumRecords: 2,
            retentionDays: 30
        )

        let first = makeRecord(text: "first")
        let second = makeRecord(text: "second")
        let third = makeRecord(text: "third")
        store.append(first)
        store.append(second)
        store.append(third)

        XCTAssertEqual(store.records.map(\.text), ["third", "second"])
    }

    func testPreviewStoreIsReadyAndFixtureBacked() {
        let store = LocalVoiceStore.preview()

        XCTAssertEqual(store.runtime.state, .ready)
        XCTAssertTrue(store.runtime.privacyVerified)
        XCTAssertEqual(store.records.count, 3)
        XCTAssertGreaterThan(store.todayWordCount, 0)
    }

    private func makeRecord(
        text: String,
        recordingMs: Double = 1_000,
        finishMs: Double = 500
    ) -> LocalVoiceRecord {
        LocalVoiceRecord(
            createdAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
            rawText: text,
            polishedText: text,
            applicationName: "Tests",
            bundleIdentifier: "com.cipherholdings.tests",
            modeName: "Default",
            engineName: "Test engine",
            language: "en",
            recordingMilliseconds: recordingMs,
            finishMilliseconds: finishMs
        )
    }
}
