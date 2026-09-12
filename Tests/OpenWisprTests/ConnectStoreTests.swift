import Foundation
import XCTest
@testable import OpenWisprLib

final class ConnectStoreTests: XCTestCase {
    func testCandidateRequiresTwoDistinctSources() {
        let store = makeStore()
        let first = UUID()

        store.observe(from: "cipher cough", to: "CipherOS", sourceRecordID: first)
        store.observe(from: "cipher cough", to: "CipherOS", sourceRecordID: first)
        XCTAssertTrue(store.pendingCandidates.isEmpty)

        store.observe(from: "Cipher cough", to: "CipherOS", sourceRecordID: UUID())
        XCTAssertEqual(store.pendingCandidates.count, 1)
        XCTAssertEqual(store.pendingCandidates[0].occurrenceCount, 2)
    }

    func testDismissedCandidateDoesNotReappear() {
        let store = makeStore()
        store.observe(from: "cipher cough", to: "CipherOS", sourceRecordID: UUID())
        store.observe(from: "cipher cough", to: "CipherOS", sourceRecordID: UUID())
        let candidate = store.pendingCandidates[0]

        store.dismiss(candidate)
        store.observe(from: "cipher cough", to: "CipherOS", sourceRecordID: UUID())

        XCTAssertTrue(store.pendingCandidates.isEmpty)
    }

    func testCandidatesPersistAcrossReload() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("connect.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ConnectStore(storageURL: file)
        first.observe(from: "cipher cough", to: "CipherOS", sourceRecordID: UUID())
        first.observe(from: "cipher cough", to: "CipherOS", sourceRecordID: UUID())

        let reloaded = ConnectStore(storageURL: file)

        XCTAssertEqual(reloaded.pendingCandidates.count, 1)
        XCTAssertEqual(reloaded.pendingCandidates[0].occurrenceCount, 2)
    }

    private func makeStore() -> ConnectStore {
        ConnectStore(
            storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            persistenceEnabled: false
        )
    }
}
