import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @ObservedObject var store: FileTranscriptionStore
    @State private var dropTargeted = false
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                PageHeader(
                    eyebrow: "LOCAL FILE WORKSPACE",
                    title: "Files",
                    subtitle: "Turn recordings into reusable transcripts and captions without uploading them."
                )
                Spacer()
                Button(action: chooseFiles) {
                    Label("Add files", systemImage: "plus")
                }
                .buttonStyle(AccentButtonStyle())
            }

            HStack(spacing: 12) {
                FileWorkspaceMetric(
                    label: "QUEUE",
                    value: store.activeCount.formatted(),
                    detail: "processing locally",
                    symbol: "list.number"
                )
                FileWorkspaceMetric(
                    label: "COMPLETED",
                    value: store.completedCount.formatted(),
                    detail: "export-ready",
                    symbol: "checkmark.circle"
                )
                FileWorkspaceMetric(
                    label: "EXPORTS",
                    value: "5",
                    detail: "formats ready",
                    symbol: "square.and.arrow.up"
                )
            }

            FileDropZone(targeted: dropTargeted, chooseFiles: chooseFiles)
                .onDrop(
                    of: [UTType.fileURL.identifier],
                    isTargeted: $dropTargeted,
                    perform: acceptProviders
                )

            if let exportError {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(LocalVoiceTheme.warning)
                    Text(exportError)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(LocalVoiceTheme.secondary)
                    Spacer()
                    Button {
                        self.exportError = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LocalVoiceTheme.warning.opacity(0.08))
                )
            }

            if store.jobs.isEmpty {
                EmptyState(
                    symbol: "doc.badge.plus",
                    title: "Drop a recording to begin",
                    detail: "Audio and video are normalized into temporary local chunks, transcribed, then deleted."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.jobs) { job in
                            FileJobCard(
                                job: job,
                                cancel: { store.cancel(id: job.id) },
                                copy: { copy(job) },
                                export: { export(job, format: $0) }
                            )
                        }
                    }
                }
            }
        }
        .padding(32)
        .background(LocalVoiceTheme.background)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add recordings to Local Voice"
        panel.message =
            "Files are processed locally. Local Voice does not retain a copy of the source audio."
        panel.prompt = "Add files"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        panel.begin { response in
            guard response == .OK else { return }
            store.enqueue(urls: panel.urls)
        }
    }

    private func acceptProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(
                UTType.fileURL.identifier
            )
        }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(
                        dataRepresentation: data,
                        relativeTo: nil
                    )
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    store.enqueue(urls: [url])
                }
            }
        }
        return true
    }

    private func copy(_ job: FileTranscriptionJob) {
        guard job.status == .completed else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            job.transcript,
            forType: .string
        )
    }

    private func export(
        _ job: FileTranscriptionJob,
        format: FileTranscriptFormat
    ) {
        do {
            let data = try store.exportData(for: job, format: format)
            let panel = NSSavePanel()
            panel.title = "Export Local Voice transcript"
            panel.nameFieldStringValue =
                job.filenameStem + "." + format.rawValue
            panel.allowedContentTypes = [
                UTType(filenameExtension: format.rawValue) ?? .data,
            ]
            panel.canCreateDirectories = true
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    return
                }
                do {
                    try data.write(to: url, options: [.atomic])
                } catch {
                    DispatchQueue.main.async {
                        exportError =
                            "Export failed: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct FileDropZone: View {
    let targeted: Bool
    let chooseFiles: () -> Void

    var body: some View {
        Button(action: chooseFiles) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LocalVoiceTheme.accent.opacity(0.1))
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(LocalVoiceTheme.accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        targeted
                            ? "Release to add files"
                            : "Drop audio or video here"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    Text(
                        "WAV, AIFF, CAF, MP3, M4A, FLAC, OGG, WebM, MP4, MOV, or M4V · up to 4 hours"
                    )
                    .font(.system(size: 10.5))
                    .foregroundColor(LocalVoiceTheme.muted)
                }
                Spacer()
                Text("LOCAL ONLY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundColor(LocalVoiceTheme.accent)
            }
            .foregroundColor(LocalVoiceTheme.primary)
            .padding(.horizontal, 16)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        targeted
                            ? LocalVoiceTheme.accent.opacity(0.07)
                            : LocalVoiceTheme.panel
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        targeted
                            ? LocalVoiceTheme.accent
                            : LocalVoiceTheme.line,
                        style: StrokeStyle(
                            lineWidth: targeted ? 1.5 : 1,
                            dash: targeted ? [5, 4] : []
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FileWorkspaceMetric: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(LocalVoiceTheme.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LocalVoiceTheme.accent.opacity(0.09))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundColor(LocalVoiceTheme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(value)
                        .font(
                            .system(
                                size: 18,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(LocalVoiceTheme.secondary)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 66)
        .cardStyle()
    }
}

private struct FileJobCard: View {
    let job: FileTranscriptionJob
    let cancel: () -> Void
    let copy: () -> Void
    let export: (FileTranscriptFormat) -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(statusColor.opacity(0.1))
                    Image(systemName: statusSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(statusColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.filename)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(job.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(LocalVoiceTheme.muted)
                }
                Spacer()
                SmallTag(text: statusLabel)
                if job.status == .completed {
                    Button {
                        copy()
                        copied = true
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 1.5
                        ) { copied = false }
                    } label: {
                        Image(
                            systemName: copied
                                ? "checkmark"
                                : "doc.on.doc"
                        )
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(LocalVoiceTheme.raised)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Copy transcript")

                    Menu {
                        ForEach(
                            FileTranscriptFormat.allCases,
                            id: \.self
                        ) { format in
                            Button(format.label) {
                                export(format)
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(LocalVoiceTheme.raised)
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28)
                    .help("Export transcript")
                } else if job.status == .queued || job.status.isActive {
                    Button("Cancel", action: cancel)
                        .font(.system(size: 10.5, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundColor(LocalVoiceTheme.secondary)
                }
            }

            if job.status == .completed {
                Text(job.transcript)
                    .font(.system(size: 12.5))
                    .foregroundColor(LocalVoiceTheme.primary)
                    .lineLimit(3)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(job.engineSummary)
                    Text("•")
                    Text(job.routeSummary)
                    Text("•")
                    Text("\(job.wordCount) words")
                    Text("•")
                    Text(formatFileDuration(job.durationMilliseconds))
                    Text("•")
                    Text("\(job.segments.count) timestamped segments")
                }
                .font(.system(size: 10))
                .foregroundColor(LocalVoiceTheme.muted)
            } else if job.status == .failed {
                Text(job.errorMessage ?? "Transcription failed.")
                    .font(.system(size: 11.5))
                    .foregroundColor(LocalVoiceTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if job.status == .cancelled {
                Text("Cancelled. No temporary audio was retained.")
                    .font(.system(size: 11))
                    .foregroundColor(LocalVoiceTheme.muted)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .tint(LocalVoiceTheme.accent)
                    HStack {
                        Text(progressDetail)
                        Spacer()
                        Text("\(Int((job.progress * 100).rounded()))%")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(LocalVoiceTheme.muted)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var statusLabel: String {
        switch job.status {
        case .queued: return "QUEUED"
        case .normalizing: return "PREPARING"
        case .transcribing: return "TRANSCRIBING"
        case .completed: return "READY"
        case .failed: return "NEEDS ATTENTION"
        case .cancelled: return "CANCELLED"
        }
    }

    private var statusSymbol: String {
        switch job.status {
        case .queued: return "clock"
        case .normalizing: return "waveform.path"
        case .transcribing: return "waveform"
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        case .cancelled: return "xmark"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .queued: return LocalVoiceTheme.muted
        case .normalizing, .transcribing: return LocalVoiceTheme.info
        case .completed: return LocalVoiceTheme.accent
        case .failed: return LocalVoiceTheme.danger
        case .cancelled: return LocalVoiceTheme.muted
        }
    }

    private var progressDetail: String {
        switch job.status {
        case .normalizing:
            return "Converting to temporary mono 16 kHz audio"
        case .transcribing:
            return "Transcribing timestamped local chunks"
        default:
            return "Waiting for the local engine"
        }
    }
}

private func formatFileDuration(_ milliseconds: Int) -> String {
    let seconds = max(0, milliseconds / 1_000)
    let hours = seconds / 3_600
    let minutes = (seconds / 60) % 60
    let remainder = seconds % 60
    if hours > 0 {
        return String(
            format: "%d:%02d:%02d",
            hours,
            minutes,
            remainder
        )
    }
    return String(format: "%d:%02d", minutes, remainder)
}

private extension FileTranscriptionJob {
    var filenameStem: String {
        let stem = (filename as NSString).deletingPathExtension
        return stem.isEmpty ? "Local Voice transcript" : stem
    }
}
