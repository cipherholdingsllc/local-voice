import AppKit
import Foundation
import XCTest
@testable import OpenWisprLib

final class ArtifactStoreTests: XCTestCase {
    func testArtifactTypeAndReuseOutcomeCoverage() {
        XCTAssertEqual(
            ArtifactType.allCases.map(\.rawValue),
            [
                "prompt", "note", "task", "decision", "ideaBrief",
                "checklist", "reusableInstruction", "skillCandidate",
            ]
        )
        XCTAssertEqual(
            ReuseOutcome.allCases.map(\.rawValue),
            ["helpful", "edited", "rejected"]
        )
    }

    func testSaveUpsertsByID() {
        let (store, _) = makeStore()
        var artifact = makeArtifact(content: "v1")

        store.save(artifact)
        artifact.content = "v2"
        store.save(artifact)

        XCTAssertEqual(store.artifacts.count, 1)
        XCTAssertEqual(store.artifact(id: artifact.id)?.content, "v2")
    }

    func testApproveSetsApprovedAt() {
        let (store, _) = makeStore()
        let artifact = makeArtifact()
        store.save(artifact)

        XCTAssertEqual(store.artifact(id: artifact.id)?.isApproved, false)

        store.approve(store.artifact(id: artifact.id)!)

        let approved = store.artifact(id: artifact.id)
        XCTAssertEqual(approved?.isApproved, true)
        XCTAssertNotNil(approved?.approvedAt)
    }

    func testRecordReuseAppendsAndPersistsAcrossReload() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-reuse-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("artifacts.json")
        let provenance = directory.appendingPathComponent("artifacts-provenance.jsonl")
        let exportDir = directory.appendingPathComponent("Artifacts")

        let store = ArtifactStore(
            storageURL: storage,
            provenanceURL: provenance,
            exportDir: exportDir
        )
        let artifact = makeArtifact()
        store.save(artifact)

        store.recordReuse(artifact, outcome: .helpful, note: "used in standup")
        store.recordReuse(store.artifact(id: artifact.id)!, outcome: .edited)

        XCTAssertEqual(store.artifact(id: artifact.id)?.reuseEvents.count, 2)
        XCTAssertEqual(
            store.artifact(id: artifact.id)?.reuseEvents.first?.outcome,
            .helpful
        )
        XCTAssertEqual(
            store.artifact(id: artifact.id)?.reuseEvents.first?.note,
            "used in standup"
        )

        let reloaded = ArtifactStore(
            storageURL: storage,
            provenanceURL: provenance,
            exportDir: exportDir
        )
        XCTAssertEqual(reloaded.artifact(id: artifact.id)?.reuseEvents.count, 2)

        let provenanceText = try? String(contentsOf: provenance, encoding: .utf8)
        XCTAssertTrue(provenanceText?.contains("reuse:helpful") == true)
        XCTAssertTrue(provenanceText?.contains("reuse:edited") == true)
    }

    func testExportWritesMarkdownHeaderAndProvenance() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exportDir = directory.appendingPathComponent("Artifacts")
        let provenance = directory.appendingPathComponent("artifacts-provenance.jsonl")

        var artifact = makeArtifact(
            type: .checklist,
            content: "- [ ] edited by operator",
            engine: "template",
            generatedContent: "- [ ] raw draft"
        )
        store.save(artifact)
        store.approve(store.artifact(id: artifact.id)!)
        artifact = try XCTUnwrap(store.artifact(id: artifact.id))

        let exportedURL = try XCTUnwrap(store.export(artifact))
        XCTAssertEqual(
            exportedURL,
            exportDir.appendingPathComponent("\(artifact.id.uuidString).md")
        )

        let markdown = try String(contentsOf: exportedURL, encoding: .utf8)
        XCTAssertTrue(markdown.hasPrefix("---\n"))
        XCTAssertTrue(markdown.contains(
            "source: local-voice://record/\(artifact.sourceTranscriptId.uuidString)"
        ))
        XCTAssertTrue(markdown.contains("artifactType: checklist"))
        XCTAssertTrue(markdown.contains("generatedBy: template"))
        XCTAssertTrue(markdown.contains("approved: true"))
        XCTAssertTrue(markdown.contains("editedAfterGeneration: true"))
        XCTAssertTrue(markdown.contains("- [ ] edited by operator"))

        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            markdown,
            "export must copy the exported Markdown to the clipboard"
        )

        var persisted = try XCTUnwrap(store.artifact(id: artifact.id))
        XCTAssertEqual(persisted.exportCount, 1)
        XCTAssertNotNil(persisted.exportedAt)

        store.export(persisted)
        persisted = try XCTUnwrap(store.artifact(id: artifact.id))
        XCTAssertEqual(persisted.exportCount, 2)

        let provenanceText = try String(contentsOf: provenance, encoding: .utf8)
        XCTAssertTrue(provenanceText.contains(artifact.id.uuidString))
        XCTAssertTrue(provenanceText.contains("\"action\":\"export\""))
    }

    func testDeleteRemovesRecordAndExportedFile() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifact = makeArtifact()
        store.save(artifact)
        let exportedURL = try XCTUnwrap(store.export(artifact))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))

        store.delete(store.artifact(id: artifact.id)!)

        XCTAssertNil(store.artifact(id: artifact.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportedURL.path))
    }

    func testDeleteArtifactsSourcingFromCascades() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceID = UUID()
        let first = makeArtifact(sourceTranscriptId: sourceID, content: "a")
        let second = makeArtifact(sourceTranscriptId: sourceID, content: "b")
        let unrelated = makeArtifact(sourceTranscriptId: UUID(), content: "keep")
        store.save(first)
        store.save(second)
        store.save(unrelated)
        let exportedURL = try XCTUnwrap(store.export(first))

        XCTAssertEqual(store.artifacts(sourcingFrom: sourceID).count, 2)

        store.deleteArtifacts(sourcingFrom: sourceID)

        XCTAssertTrue(store.artifacts(sourcingFrom: sourceID).isEmpty)
        XCTAssertNotNil(store.artifact(id: unrelated.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportedURL.path))
    }

    func testUserEditedFlagSemantics() {
        let noDraft = makeArtifact(generatedContent: nil)
        XCTAssertFalse(noDraft.userEdited)

        let untouched = makeArtifact(
            content: "same text",
            generatedContent: "same text"
        )
        XCTAssertFalse(untouched.userEdited)

        let edited = makeArtifact(
            content: "operator rewrite",
            generatedContent: "same text"
        )
        XCTAssertTrue(edited.userEdited)

        XCTAssertFalse(makeArtifact().isApproved)
    }

    func testLegacyArtifactJSONDecodesWithDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storage = directory.appendingPathComponent("artifacts.json")

        let legacyID = UUID()
        let legacySource = UUID()
        let legacyJSON = """
        [
          {
            "id": "\(legacyID.uuidString)",
            "sourceTranscriptId": "\(legacySource.uuidString)",
            "type": "note",
            "content": "legacy body",
            "generatedAt": "2024-01-02T03:04:05Z"
          }
        ]
        """
        try legacyJSON.write(to: storage, atomically: true, encoding: .utf8)

        let store = ArtifactStore(
            storageURL: storage,
            provenanceURL: directory.appendingPathComponent("prov.jsonl"),
            exportDir: directory.appendingPathComponent("Artifacts")
        )

        let artifact = try XCTUnwrap(store.artifact(id: legacyID))
        XCTAssertEqual(artifact.content, "legacy body")
        XCTAssertEqual(artifact.sourceTranscriptId, legacySource)
        XCTAssertNil(artifact.engine)
        XCTAssertNil(artifact.generatedContent)
        XCTAssertTrue(artifact.reuseEvents.isEmpty)
        XCTAssertEqual(artifact.exportCount, 0)
        XCTAssertFalse(artifact.isApproved)
        XCTAssertFalse(artifact.userEdited)
    }

    func testTemplateDraftsContainTypeScaffolding() {
        let record = makeRecord(
            text: "Ship the artifact export. It should write markdown files. Include a YAML header."
        )

        var drafts: [ArtifactType: String] = [:]
        for type in ArtifactType.allCases {
            let draft = UsefulTransformer.shared.draft(
                record: record,
                type: type,
                engine: .template
            )
            XCTAssertEqual(draft.engine, .template)
            XCTAssertFalse(draft.content.isEmpty, "\(type.rawValue) draft empty")
            drafts[type] = draft.content
        }

        XCTAssertTrue(drafts[.prompt]!.contains("## What to do"))
        XCTAssertTrue(drafts[.prompt]!.contains("## Context"))
        XCTAssertTrue(drafts[.note]!.contains(record.text))
        XCTAssertTrue(drafts[.task]!.contains("- [ ] Ship the artifact export."))
        XCTAssertTrue(drafts[.decision]!.contains("**Decided:**"))
        XCTAssertTrue(drafts[.decision]!.contains("**Status:** draft"))
        XCTAssertTrue(drafts[.ideaBrief]!.contains("**Idea:**"))
        XCTAssertTrue(drafts[.ideaBrief]!.contains("**Open questions:**"))
        XCTAssertEqual(
            drafts[.checklist]!
                .split(separator: "\n")
                .filter { $0.hasPrefix("- [ ] ") }
                .count,
            3
        )
        XCTAssertTrue(drafts[.reusableInstruction]!.contains("**When:**"))
        XCTAssertTrue(drafts[.reusableInstruction]!.contains("**Rule:**"))
        XCTAssertTrue(drafts[.skillCandidate]!.contains("**Procedure:**"))
        XCTAssertTrue(drafts[.skillCandidate]!.contains("**Use when:**"))
    }

    // MARK: Fixtures

    private func makeStore() -> (ArtifactStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-store-\(UUID().uuidString)")
        let store = ArtifactStore(
            storageURL: directory.appendingPathComponent("artifacts.json"),
            provenanceURL: directory.appendingPathComponent("artifacts-provenance.jsonl"),
            exportDir: directory.appendingPathComponent("Artifacts")
        )
        return (store, directory)
    }

    private func makeArtifact(
        sourceTranscriptId: UUID = UUID(),
        type: ArtifactType = .note,
        content: String = "draft content",
        engine: String? = "template",
        generatedContent: String? = nil
    ) -> LocalVoiceArtifact {
        LocalVoiceArtifact(
            sourceTranscriptId: sourceTranscriptId,
            type: type,
            content: content,
            engine: engine,
            generatedContent: generatedContent
        )
    }

    private func makeRecord(text: String) -> LocalVoiceRecord {
        LocalVoiceRecord(
            createdAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
            rawText: text,
            polishedText: text,
            applicationName: "Tests",
            bundleIdentifier: "com.cipherholdings.tests",
            modeName: "Default",
            engineName: "Test engine",
            language: "en",
            recordingMilliseconds: 1_000,
            finishMilliseconds: 500
        )
    }
}
