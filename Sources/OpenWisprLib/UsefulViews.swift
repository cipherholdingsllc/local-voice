import Foundation
import SwiftUI

public struct ArtifactsView: View {
    @ObservedObject private var store: ArtifactStore = .shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                eyebrow: "MAKE USEFUL",
                title: "Artifacts",
                subtitle: "Reusable drafts generated from your dictations."
            )

            if store.artifacts.isEmpty {
                EmptyState(
                    symbol: "doc.plaintext",
                    title: "No artifacts yet",
                    detail: "Select a transcript in History and tap the sparkles to make it useful."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.artifacts) { artifact in
                            ArtifactCard(artifact: artifact)
                        }
                    }
                }
            }
        }
        .padding(32)
        .background(LocalVoiceTheme.background)
    }
}

private struct ArtifactCard: View {
    let artifact: LocalVoiceArtifact
    @State private var exported = false
    @State private var copied = false
    @State private var skillInstalled = false
    @ObservedObject private var store: ArtifactStore = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: artifact.type.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(LocalVoiceTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artifact.type.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(artifact.generatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10.5))
                            .foregroundColor(LocalVoiceTheme.muted)
                    }
                }
                Spacer()
                SmallTag(text: artifact.isApproved ? "Approved" : "Draft")
                SmallTag(text: "Export \(artifact.exportCount)")
                if !artifact.isApproved {
                    Button {
                        store.approve(artifact)
                    } label: {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(LocalVoiceTheme.accent)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(LocalVoiceTheme.raised))
                    }
                    .buttonStyle(.plain)
                    .help("Approve artifact")
                }
                Button {
                    _ = store.export(artifact)
                    exported = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exported = false }
                } label: {
                    Image(systemName: exported ? "checkmark" : "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(exported ? LocalVoiceTheme.accent : LocalVoiceTheme.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(LocalVoiceTheme.raised))
                }
                .buttonStyle(.plain)
                .help("Export to Markdown and copy to clipboard")
                if ArtifactStore.isSkillExportable(artifact) {
                    Button {
                        skillInstalled = store.exportSkill(artifact) != nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { skillInstalled = false }
                    } label: {
                        Image(systemName: (skillInstalled || artifact.skillSlug != nil) ? "checkmark" : "puzzlepiece.extension")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor((skillInstalled || artifact.skillSlug != nil) ? LocalVoiceTheme.accent : LocalVoiceTheme.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(LocalVoiceTheme.raised))
                    }
                    .buttonStyle(.plain)
                    .help(artifact.skillSlug.map { "Skill installed at ~/.config/devin/skills/\($0) — reinstall" } ?? "Install as agent skill (SKILL.md)")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(artifact.content, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(copied ? LocalVoiceTheme.accent : LocalVoiceTheme.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(LocalVoiceTheme.raised))
                }
                .buttonStyle(.plain)
                .help("Copy content")
                Button {
                    store.delete(artifact)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(LocalVoiceTheme.danger)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(LocalVoiceTheme.raised))
                }
                .buttonStyle(.plain)
                .help("Delete artifact")
            }

            Text(artifact.content)
                .font(.system(size: 13))
                .foregroundColor(LocalVoiceTheme.primary)
                .lineSpacing(4)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                SmallTag(text: artifact.engine == "ollama" ? "Ollama" : "Template")
                if artifact.userEdited {
                    SmallTag(text: "Edited")
                }
                if !artifact.reuseEvents.isEmpty {
                    SmallTag(text: "Reuse \(artifact.reuseEvents.count)")
                    if let latest = artifact.reuseEvents.last {
                        SmallTag(text: latest.outcome.title)
                    }
                }
                Spacer()
                Menu {
                    ForEach(ReuseOutcome.allCases) { outcome in
                        Button {
                            store.recordReuse(artifact, outcome: outcome)
                        } label: {
                            Label(outcome.title, systemImage: outcome.symbol)
                        }
                    }
                } label: {
                    Text("Mark reused")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(LocalVoiceTheme.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 23)
                        .background(Capsule().fill(LocalVoiceTheme.raised))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Record a reuse outcome")
            }
        }
        .padding(17)
        .cardStyle()
    }
}

public struct MakeUsefulView: View {
    let record: LocalVoiceRecord
    @Environment(\.dismiss) private var dismiss
    @State private var type: ArtifactType = .prompt
    @State private var engine: UsefulEngine = .ollama
    @State private var content = ""
    @State private var isGenerating = false
    @State private var isSaved = false
    @State private var isExported = false
    @State private var generatedDraft: String?
    @State private var resolvedEngine: UsefulEngine?
    @State private var savedArtifactId: UUID?
    @ObservedObject private var store: ArtifactStore = .shared

    public init(record: LocalVoiceRecord) {
        self.record = record
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                eyebrow: "MAKE USEFUL",
                title: "Draft from dictation",
                subtitle: "Choose an artifact type and engine. Edit the draft, then save or export."
            )

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Artifact type")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LocalVoiceTheme.muted)
                    Picker("", selection: $type) {
                        ForEach(ArtifactType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Engine")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LocalVoiceTheme.muted)
                    Picker("", selection: $engine) {
                        ForEach(UsefulEngine.allCases, id: \.self) { engine in
                            Text(engine.title).tag(engine)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            if isGenerating {
                ProgressView("Generating draft…")
                    .foregroundColor(LocalVoiceTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .cardStyle()
            } else if content.isEmpty {
                EmptyState(
                    symbol: "sparkles",
                    title: "Ready to draft",
                    detail: "Tap Generate to turn this transcript into a reusable artifact."
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Draft")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(LocalVoiceTheme.muted)
                        Spacer()
                        if let generatedDraft {
                            Text(content == generatedDraft ? "Inferred draft — edit before approving" : "Edited")
                                .font(.system(size: 10.5))
                                .foregroundColor(LocalVoiceTheme.muted)
                        }
                    }
                    TextEditor(text: $content)
                        .font(.system(size: 13))
                        .foregroundColor(LocalVoiceTheme.primary)
                        .frame(minHeight: 140, maxHeight: .infinity)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .cardStyle()
                }
            }

            HStack(spacing: 10) {
                Button("Generate") { generate() }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(isGenerating)
                Button("Save") { save() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(content.isEmpty)
                Button(isExported ? "Exported" : "Export") { save(); export() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(content.isEmpty)
                if let savedArtifactId, let saved = store.artifact(id: savedArtifactId) {
                    Button(saved.isApproved ? "Approved" : "Approve") {
                        store.approve(saved)
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(saved.isApproved)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
            }

            if isSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(LocalVoiceTheme.accent)
                    Text("Saved to Artifacts.")
                        .font(.system(size: 12))
                        .foregroundColor(LocalVoiceTheme.secondary)
                }
            }
        }
        .padding(32)
        .background(LocalVoiceTheme.background)
        .frame(minWidth: 540, minHeight: 360)
    }

    private func generate() {
        isGenerating = true
        content = ""
        Task.detached(priority: .userInitiated) { [record, type, engine] in
            let draft = UsefulTransformer.shared.draft(record: record, type: type, engine: engine)
            await MainActor.run {
                content = draft.content
                generatedDraft = draft.content
                resolvedEngine = draft.engine
                isGenerating = false
            }
        }
    }

    private func save() {
        let artifact: LocalVoiceArtifact
        if let savedArtifactId, var existing = store.artifact(id: savedArtifactId) {
            existing.content = content
            artifact = existing
        } else {
            artifact = LocalVoiceArtifact(
                sourceTranscriptId: record.id,
                type: type,
                content: content,
                engine: resolvedEngine?.rawValue,
                generatedContent: generatedDraft
            )
            savedArtifactId = artifact.id
        }
        store.save(artifact)
        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { isSaved = false }
    }

    private func export() {
        guard let savedArtifactId, let artifact = store.artifact(id: savedArtifactId) else { return }
        _ = store.export(artifact)
        isExported = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isExported = false }
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(LocalVoiceTheme.background)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LocalVoiceTheme.secondary.opacity(configuration.isPressed ? 0.78 : 1))
            )
    }
}

public struct RelatedRecordsView: View {
    let record: LocalVoiceRecord
    @Environment(\.dismiss) private var dismiss

    public init(record: LocalVoiceRecord) {
        self.record = record
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                eyebrow: "CONNECT",
                title: "Related",
                subtitle: "Other transcripts that share words with this one."
            )

            let related = LocalVoiceStore.shared.related(to: record)

            if related.isEmpty {
                EmptyState(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "No related transcripts",
                    detail: "Similar transcripts will surface here as your history grows."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(related) { record in
                            RelatedRecordRow(record: record)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(32)
        .background(LocalVoiceTheme.background)
        .frame(minWidth: 480, minHeight: 300)
    }
}

private struct RelatedRecordRow: View {
    let record: LocalVoiceRecord

    var body: some View {
        HStack(spacing: 14) {
            AppGlyph(name: record.applicationName)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(LocalVoiceTheme.primary)
                    .lineLimit(2)
                HStack(spacing: 7) {
                    Text(record.applicationName)
                    Text("•")
                    Text(record.modeName)
                    Text("•")
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.system(size: 10.5))
                .foregroundColor(LocalVoiceTheme.muted)
            }
            Spacer()
            Text("\(record.wordCount) words")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(LocalVoiceTheme.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
    }
}
