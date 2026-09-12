import SwiftUI

public struct ConnectView: View {
    @ObservedObject private var connect: ConnectStore = .shared
    @ObservedObject private var history: LocalVoiceStore = .shared
    @State private var enabled = Config.load().connectIntelligenceEnabled?.value ?? false
    @State private var statusMessage = ""
    private let reloadConfiguration: () -> Void

    public init(reloadConfiguration: @escaping () -> Void = {}) {
        self.reloadConfiguration = reloadConfiguration
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "CONNECT",
                    title: "Patterns",
                    subtitle: "Review recurring corrections and related thoughts derived locally from retained history."
                )

                if !enabled {
                    disabledState
                } else {
                    controls
                    correctionSection
                    clusterSection
                }
            }
            .padding(32)
        }
        .background(LocalVoiceTheme.background)
        .onAppear {
            enabled = Config.load().connectIntelligenceEnabled?.value ?? false
            if enabled { connect.rebuildAsync(records: history.records) }
        }
    }

    private var disabledState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(LocalVoiceTheme.accent)
            Text("Connect intelligence is off")
                .font(.system(size: 16, weight: .semibold))
            Text("Enable it to build a local review queue. Corrections require two separate observations and your approval before they change dictation.")
                .font(.system(size: 13))
                .foregroundColor(LocalVoiceTheme.secondary)
                .lineSpacing(4)
            Button("Enable Connect") {
                var config = Config.load()
                config.connectIntelligenceEnabled = FlexBool(true)
                if (try? config.save()) != nil {
                    enabled = true
                    reloadConfiguration()
                    connect.rebuildAsync(records: history.records)
                }
            }
            .buttonStyle(AccentButtonStyle())
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var controls: some View {
        HStack {
            if let date = connect.lastRebuiltAt {
                Text("Rebuilt \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundColor(LocalVoiceTheme.muted)
            } else {
                Text("Building local index…")
                    .font(.system(size: 11))
                    .foregroundColor(LocalVoiceTheme.muted)
            }
            Spacer()
            QuietButton(title: "Refresh", symbol: "arrow.clockwise") {
                connect.rebuildAsync(records: history.records)
            }
        }
    }

    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Correction candidates", detail: "Two observations required")
            if connect.pendingCandidates.isEmpty {
                EmptyState(
                    symbol: "text.badge.checkmark",
                    title: "No recurring corrections yet",
                    detail: "Candidates appear only after the same safe correction is observed in two separate dictations."
                )
            } else {
                ForEach(connect.pendingCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(candidate.from) → \(candidate.to)")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            SmallTag(text: "\(candidate.occurrenceCount) observations")
                        }
                        Text("Observed \(candidate.firstObservedAt.formatted(date: .abbreviated, time: .omitted)) – \(candidate.lastObservedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 11))
                            .foregroundColor(LocalVoiceTheme.muted)
                        HStack(spacing: 10) {
                            Button("Approve") {
                                statusMessage = connect.approve(candidate) ? "Correction approved." : "Correction could not be approved."
                            }
                            .buttonStyle(AccentButtonStyle())
                            QuietButton(title: "Dismiss", symbol: "xmark") {
                                connect.dismiss(candidate)
                                statusMessage = "Correction dismissed."
                            }
                        }
                    }
                    .padding(17)
                    .cardStyle()
                }
            }
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(LocalVoiceTheme.secondary)
            }
        }
    }

    private var clusterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Related thoughts", detail: "Deterministic local matching")
            if connect.clusters.isEmpty {
                EmptyState(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "No strong clusters yet",
                    detail: "Distinctive repeated phrases across retained transcripts will collect here."
                )
            } else {
                ForEach(connect.clusters) { cluster in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(cluster.title.capitalized)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            SmallTag(text: "\(cluster.recordIDs.count) thoughts")
                        }
                        Text(cluster.sharedTerms.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundColor(LocalVoiceTheme.accent)
                        ForEach(history.records.filter { cluster.recordIDs.contains($0.id) }.prefix(3)) { record in
                            Text(record.text)
                                .font(.system(size: 12))
                                .foregroundColor(LocalVoiceTheme.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(17)
                    .cardStyle()
                }
            }
        }
    }
}
