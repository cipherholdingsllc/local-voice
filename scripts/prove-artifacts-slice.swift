import Foundation

@main
enum ArtifactsSliceProve {
    static func expect(_ cond: Bool, _ message: String) {
        if !cond {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func expectEqual(_ got: String, _ want: String, _ label: String) {
        expect(got == want, "\(label)\n  got:  \(got)\n  want: \(want)")
    }

    static func makeRecord(text: String) -> LocalVoiceRecord {
        LocalVoiceRecord(
            createdAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
            rawText: text,
            polishedText: text,
            applicationName: "Prove",
            bundleIdentifier: "com.cipherholdings.prove",
            modeName: "Default",
            engineName: "Test engine",
            language: "en",
            recordingMilliseconds: 1_000,
            finishMilliseconds: 500
        )
    }

    static func makeArtifact(
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

    static func main() {
        // MARK: Enum coverage

        expectEqual(
            ArtifactType.allCases.map(\.rawValue).joined(separator: ","),
            "prompt,note,task,decision,ideaBrief,checklist,reusableInstruction,skillCandidate",
            "ArtifactType allCases"
        )
        expectEqual(
            ReuseOutcome.allCases.map(\.rawValue).joined(separator: ","),
            "helpful,edited,rejected",
            "ReuseOutcome allCases"
        )

        // MARK: LocalVoiceArtifact computed flags

        let fresh = makeArtifact()
        expect(!fresh.isApproved, "new artifact should not be approved")
        expect(!fresh.userEdited, "nil generatedContent => not userEdited")
        expect(fresh.exportCount == 0, "new artifact exportCount")
        expect(fresh.reuseEvents.isEmpty, "new artifact reuseEvents")

        let unedited = makeArtifact(generatedContent: "same text")
        var editedCopy = unedited
        editedCopy.content = "same text"
        expect(!editedCopy.userEdited, "generatedContent == content => not userEdited")
        editedCopy.content = "operator rewrite"
        expect(editedCopy.userEdited, "generatedContent != content => userEdited")

        // MARK: ArtifactStore save / upsert / approve

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifacts-prove-\(UUID().uuidString)")
        let storage = directory.appendingPathComponent("artifacts.json")
        let provenance = directory.appendingPathComponent("artifacts-provenance.jsonl")
        let exportDir = directory.appendingPathComponent("Artifacts")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ArtifactStore(
            storageURL: storage,
            provenanceURL: provenance,
            exportDir: exportDir
        )
        expect(store.artifacts.isEmpty, "fresh store should be empty")

        var artifact = makeArtifact(content: "v1")
        store.save(artifact)
        artifact.content = "v2"
        store.save(artifact)
        expect(store.artifacts.count == 1, "save must upsert by id, got \(store.artifacts.count)")
        expectEqual(store.artifact(id: artifact.id)?.content ?? "", "v2", "upsert content")
        expect(FileManager.default.fileExists(atPath: storage.path), "save persists artifacts.json")

        expect(store.artifact(id: artifact.id)?.isApproved == false, "unapproved before approve")
        store.approve(store.artifact(id: artifact.id)!)
        let approved = store.artifact(id: artifact.id)
        expect(approved?.isApproved == true, "approve sets isApproved")
        expect(approved?.approvedAt != nil, "approve sets approvedAt")

        // MARK: recordReuse appends and persists across re-init

        store.recordReuse(approved!, outcome: .helpful, note: "used in standup")
        store.recordReuse(store.artifact(id: artifact.id)!, outcome: .edited)
        expect(
            store.artifact(id: artifact.id)?.reuseEvents.count == 2,
            "recordReuse appends one event per call"
        )
        expect(
            store.artifact(id: artifact.id)?.reuseEvents.first?.outcome == .helpful,
            "first reuse outcome"
        )
        expectEqual(
            store.artifact(id: artifact.id)?.reuseEvents.first?.note ?? "",
            "used in standup",
            "reuse note"
        )

        let reloaded = ArtifactStore(
            storageURL: storage,
            provenanceURL: provenance,
            exportDir: exportDir
        )
        expect(
            reloaded.artifact(id: artifact.id)?.reuseEvents.count == 2,
            "reuseEvents persist across store re-init"
        )
        expect(reloaded.artifact(id: artifact.id)?.isApproved == true, "approval persists")

        // MARK: export writes markdown, header, provenance

        var exportable = makeArtifact(
            type: .checklist,
            content: "- [ ] edited by operator",
            engine: "template",
            generatedContent: "- [ ] raw draft"
        )
        store.save(exportable)
        store.approve(store.artifact(id: exportable.id)!)
        exportable = store.artifact(id: exportable.id)!

        let exportedURL = store.export(exportable)
        expect(exportedURL != nil, "export returns file URL")
        let expectedURL = exportDir.appendingPathComponent("\(exportable.id.uuidString).md")
        expect(exportedURL == expectedURL, "export URL is <exportDir>/<id>.md")
        expect(
            FileManager.default.fileExists(atPath: expectedURL.path),
            "export writes markdown file"
        )

        let markdown = (try? String(contentsOf: expectedURL, encoding: .utf8)) ?? ""
        expect(markdown.hasPrefix("---\n"), "markdown starts with YAML header")
        expect(
            markdown.contains("source: local-voice://record/\(exportable.sourceTranscriptId.uuidString)"),
            "header source line"
        )
        expect(markdown.contains("artifactType: checklist"), "header artifactType")
        expect(markdown.contains("generatedBy: template"), "header generatedBy")
        expect(markdown.contains("approved: true"), "header approved")
        expect(markdown.contains("editedAfterGeneration: true"), "header editedAfterGeneration")
        expect(markdown.contains("- [ ] edited by operator"), "export body is content")

        let afterExport = store.artifact(id: exportable.id)
        expect(afterExport?.exportCount == 1, "export increments exportCount")
        expect(afterExport?.exportedAt != nil, "export sets exportedAt")
        store.export(afterExport!)
        expect(store.artifact(id: exportable.id)?.exportCount == 2, "second export increments")

        let provenanceText = (try? String(contentsOf: provenance, encoding: .utf8)) ?? ""
        expect(!provenanceText.isEmpty, "provenance JSONL written")
        expect(provenanceText.contains(exportable.id.uuidString), "provenance has artifactId")
        expect(provenanceText.contains("\"action\":\"export\""), "provenance export action")
        expect(provenanceText.contains("reuse:helpful"), "provenance reuse action")

        // MARK: delete removes record and file

        store.delete(store.artifact(id: exportable.id)!)
        expect(store.artifact(id: exportable.id) == nil, "delete removes record")
        expect(
            !FileManager.default.fileExists(atPath: expectedURL.path),
            "delete removes exported file"
        )

        // MARK: deleteArtifacts(sourcingFrom:) cascade

        let sourceID = UUID()
        let keptID = UUID()
        let cascadeA = makeArtifact(sourceTranscriptId: sourceID, content: "a")
        let cascadeB = makeArtifact(sourceTranscriptId: sourceID, content: "b")
        let unrelated = makeArtifact(sourceTranscriptId: keptID, content: "keep")
        store.save(cascadeA)
        store.save(cascadeB)
        store.save(unrelated)
        let cascadedFile = store.export(cascadeA)

        expect(store.artifacts(sourcingFrom: sourceID).count == 2, "sourcingFrom filter")
        store.deleteArtifacts(sourcingFrom: sourceID)
        expect(store.artifacts(sourcingFrom: sourceID).isEmpty, "cascade removes derived")
        expect(store.artifact(id: unrelated.id) != nil, "cascade keeps unrelated")
        expect(
            cascadedFile != nil
                && !FileManager.default.fileExists(atPath: cascadedFile!.path),
            "cascade removes exported files"
        )

        // MARK: backward-compatible decode of legacy artifact JSON

        let legacyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifacts-legacy-\(UUID().uuidString)")
        let legacyStorage = legacyDir.appendingPathComponent("artifacts.json")
        defer { try? FileManager.default.removeItem(at: legacyDir) }
        try? FileManager.default.createDirectory(
            at: legacyDir,
            withIntermediateDirectories: true
        )
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
        try? legacyJSON.write(to: legacyStorage, atomically: true, encoding: .utf8)

        let legacyStore = ArtifactStore(
            storageURL: legacyStorage,
            provenanceURL: legacyDir.appendingPathComponent("prov.jsonl"),
            exportDir: legacyDir.appendingPathComponent("Artifacts")
        )
        let legacy = legacyStore.artifact(id: legacyID)
        expect(legacy != nil, "legacy artifact decodes")
        expectEqual(legacy?.content ?? "", "legacy body", "legacy content")
        expect(legacy?.engine == nil, "legacy engine defaults to nil")
        expect(legacy?.generatedContent == nil, "legacy generatedContent defaults to nil")
        expect(legacy?.reuseEvents.isEmpty == true, "legacy reuseEvents defaults to []")
        expect(legacy?.exportCount == 0, "legacy exportCount defaults to 0")
        expect(legacy?.isApproved == false, "legacy isApproved false")
        expect(legacy?.userEdited == false, "legacy userEdited false")

        // MARK: UsefulTransformer template drafts

        let record = makeRecord(
            text: "Ship the artifact export. It should write markdown files. Include a YAML header."
        )
        for type in ArtifactType.allCases {
            let draft = UsefulTransformer.shared.draft(record: record, type: type, engine: .template)
            expect(draft.engine == .template, "template engine for \(type.rawValue)")
            expect(!draft.content.isEmpty, "non-empty draft for \(type.rawValue)")
        }

        let drafts = Dictionary(
            uniqueKeysWithValues: ArtifactType.allCases.map {
                ($0, UsefulTransformer.shared.draft(record: record, type: $0, engine: .template).content)
            }
        )
        expect(drafts[.prompt]!.contains("## What to do"), "prompt scaffold")
        expect(drafts[.prompt]!.contains("## Context"), "prompt context")
        expect(drafts[.note]!.contains(record.text), "note embeds transcript")
        expect(drafts[.task]!.contains("- [ ] Ship the artifact export."), "task checkbox")
        expect(drafts[.decision]!.contains("**Decided:**"), "decision scaffold")
        expect(drafts[.decision]!.contains("**Status:** draft"), "decision status")
        expect(drafts[.ideaBrief]!.contains("**Idea:**"), "ideaBrief idea")
        expect(drafts[.ideaBrief]!.contains("**Open questions:**"), "ideaBrief questions")
        let checklistLines = drafts[.checklist]!
            .split(separator: "\n")
            .filter { $0.hasPrefix("- [ ] ") }
        expect(checklistLines.count == 3, "checklist items, got \(checklistLines.count)")
        expect(drafts[.reusableInstruction]!.contains("**When:**"), "instruction when")
        expect(drafts[.reusableInstruction]!.contains("**Rule:**"), "instruction rule")
        expect(drafts[.skillCandidate]!.contains("**Procedure:**"), "skill procedure")
        expect(drafts[.skillCandidate]!.contains("**Use when:**"), "skill use-when")

        // MARK: LocalVoiceStore.delete removes record and persists

        let historyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-prove-\(UUID().uuidString)")
        let historyFile = historyDir.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: historyDir) }
        let snapshot = LocalVoiceRuntimeSnapshot(
            state: .ready,
            engineName: "Test",
            modelName: "test",
            languageName: "en",
            statusDetail: "",
            privacyVerified: true,
            whisperReady: false,
            accessibilityReady: false,
            microphoneReady: false,
            inputMonitoringReady: false,
            hotkeyReady: false
        )
        let doomed = makeRecord(text: "delete me")
        let kept = makeRecord(text: "keep me")
        let history = LocalVoiceStore(
            storageURL: historyFile,
            records: [doomed, kept],
            runtime: snapshot,
            retentionDays: 30,
            persistenceEnabled: true
        )
        history.delete(recordID: doomed.id)
        expect(history.records == [kept], "delete removes record")
        expect(
            FileManager.default.fileExists(atPath: historyFile.path),
            "delete persists history.json"
        )
        let historyReloaded = LocalVoiceStore(
            storageURL: historyFile,
            runtime: snapshot,
            retentionDays: 30,
            persistenceEnabled: true
        )
        expect(historyReloaded.records == [kept], "deletion survives reload")

        // persistenceEnabled false => no file written
        let offDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-off-\(UUID().uuidString)")
        let offFile = offDir.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: offDir) }
        let noPersist = LocalVoiceStore(
            storageURL: offFile,
            records: [makeRecord(text: "session only")],
            runtime: snapshot,
            retentionDays: 30,
            persistenceEnabled: false
        )
        noPersist.delete(recordID: noPersist.records[0].id)
        expect(noPersist.records.isEmpty, "in-memory delete still works")
        expect(
            !FileManager.default.fileExists(atPath: offFile.path),
            "persistenceEnabled false writes no file"
        )

        print("PASS: artifacts-slice prove")
    }
}
