import AppKit
import SwiftUI

public struct LocalVoiceDashboardActions {
    public var toggleRecording: () -> Void
    public var copyLast: () -> Void
    public var runPrivacyTest: () -> Void
    public var reloadConfiguration: () -> Void
    public var openConfiguration: () -> Void
    public var repairPermissions: () -> Void
    public var shortcutCaptureChanged: (Bool) -> Void
    public var setShortcut: (HotkeyConfig) -> String?

    public init(
        toggleRecording: @escaping () -> Void = {},
        copyLast: @escaping () -> Void = {},
        runPrivacyTest: @escaping () -> Void = {},
        reloadConfiguration: @escaping () -> Void = {},
        openConfiguration: @escaping () -> Void = {},
        repairPermissions: @escaping () -> Void = {},
        shortcutCaptureChanged: @escaping (Bool) -> Void = { _ in },
        setShortcut: @escaping (HotkeyConfig) -> String? = { _ in nil }
    ) {
        self.toggleRecording = toggleRecording
        self.copyLast = copyLast
        self.runPrivacyTest = runPrivacyTest
        self.reloadConfiguration = reloadConfiguration
        self.openConfiguration = openConfiguration
        self.repairPermissions = repairPermissions
        self.shortcutCaptureChanged = shortcutCaptureChanged
        self.setShortcut = setShortcut
    }
}

public struct LocalVoiceDashboard: View {
    @ObservedObject private var store: LocalVoiceStore
    @ObservedObject private var fileStore: FileTranscriptionStore
    private let actions: LocalVoiceDashboardActions
    @State private var section: DashboardSection = .home

    public init(
        store: LocalVoiceStore,
        actions: LocalVoiceDashboardActions,
        fileStore: FileTranscriptionStore = .shared,
        initialSection: String? = nil
    ) {
        self.store = store
        self.actions = actions
        self.fileStore = fileStore
        _section = State(
            initialValue: DashboardSection(rawValue: initialSection ?? "") ?? .home
        )
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 224)
            Rectangle()
                .fill(LocalVoiceTheme.line)
                .frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LocalVoiceTheme.background)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LocalVoiceTheme.accent)
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(LocalVoiceTheme.background)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("LOCAL VOICE")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.1)
                    Text("Private by design")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(LocalVoiceTheme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)

            VStack(spacing: 5) {
                ForEach(DashboardSection.allCases) { item in
                    SidebarButton(
                        section: item,
                        selected: item == section,
                        action: { section = item }
                    )
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.runtime.privacyVerified ? LocalVoiceTheme.accent : LocalVoiceTheme.warning)
                        .frame(width: 7, height: 7)
                    Text(store.runtime.privacyVerified ? "Local route verified" : "Privacy check available")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LocalVoiceTheme.secondary)
                }
                Text("Audio is not retained by default.")
                    .font(.system(size: 10.5))
                    .foregroundColor(LocalVoiceTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LocalVoiceTheme.panel)
            )
            .padding(14)
        }
        .background(LocalVoiceTheme.sidebar)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .home:
            HomeView(store: store, actions: actions)
        case .history:
            HistoryView(store: store)
        case .files:
            FileTranscriptionView(store: fileStore)
        case .modes:
            ModesView()
        case .dictionary:
            DictionaryView()
        case .models:
            ModelsView(store: store)
        case .privacy:
            PrivacyView(store: store, actions: actions)
        case .settings:
            SettingsView(actions: actions)
        }
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case home
    case history
    case files
    case modes
    case dictionary
    case models
    case privacy
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Command Center"
        case .history: return "History"
        case .files: return "Files"
        case .modes: return "Modes"
        case .dictionary: return "Dictionary"
        case .models: return "Models"
        case .privacy: return "Privacy"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .history: return "clock.arrow.circlepath"
        case .files: return "doc.badge.waveform"
        case .modes: return "slider.horizontal.3"
        case .dictionary: return "text.book.closed"
        case .models: return "cpu"
        case .privacy: return "lock.shield"
        case .settings: return "gearshape"
        }
    }
}

private struct SidebarButton: View {
    let section: DashboardSection
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundColor(selected ? LocalVoiceTheme.primary : LocalVoiceTheme.secondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? LocalVoiceTheme.selected : Color.clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LocalVoiceTheme.accent)
                        .frame(width: 3, height: 18)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct HomeView: View {
    @ObservedObject var store: LocalVoiceStore
    let actions: LocalVoiceDashboardActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "COMMAND CENTER",
                    title: greeting,
                    subtitle: "Your local voice stack is tuned, private, and ready across macOS."
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ReadyCard(store: store, actions: actions)
                            .frame(minWidth: 380)
                        RuntimeCard(store: store, actions: actions)
                            .frame(width: 300)
                    }

                    VStack(spacing: 16) {
                        ReadyCard(store: store, actions: actions)
                            .frame(maxWidth: .infinity)
                        RuntimeCard(store: store, actions: actions)
                            .frame(maxWidth: .infinity)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        metrics
                    }
                    VStack(spacing: 14) {
                        metrics
                    }
                }

                SectionHeader(title: "Recent dictations", detail: "Stored on this Mac")
                if store.records.isEmpty {
                    EmptyState(
                        symbol: "waveform.badge.plus",
                        title: "Your first dictation will appear here",
                        detail: "Hold \(Config.load().hotkeySummary()), speak naturally, and release."
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.records.prefix(4).enumerated()), id: \.element.id) { index, record in
                            RecordRow(record: record)
                            if index < min(store.records.count, 4) - 1 {
                                Rectangle()
                                    .fill(LocalVoiceTheme.line)
                                    .frame(height: 1)
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(32)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning." }
        if hour < 18 { return "Good afternoon." }
        return "Good evening."
    }

    @ViewBuilder
    private var metrics: some View {
        MetricCard(
            label: "WORDS TODAY",
            value: store.todayWordCount.formatted(),
            detail: "\(store.todayRecords.count) dictations",
            symbol: "text.word.spacing"
        )
        MetricCard(
            label: "VOICE TODAY",
            value: formatMinutes(store.todayVoiceMinutes),
            detail: "captured locally",
            symbol: "waveform"
        )
        MetricCard(
            label: "MEDIAN FINISH",
            value: formatLatency(store.medianFinishMilliseconds),
            detail: "after you stop",
            symbol: "timer"
        )
    }
}

private struct ReadyCard: View {
    @ObservedObject var store: LocalVoiceStore
    let actions: LocalVoiceDashboardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                StatusPill(
                    title: store.runtime.state.label.uppercased(),
                    color: statusColor
                )
                Spacer()
                Text(store.runtime.languageName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(LocalVoiceTheme.muted)
            }

            Spacer(minLength: 18)

            HStack(spacing: 20) {
                Button(action: actions.toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(LocalVoiceTheme.accent)
                            .shadow(color: LocalVoiceTheme.accent.opacity(0.18), radius: 18, y: 8)
                        Image(systemName: store.runtime.state == .listening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(LocalVoiceTheme.background)
                    }
                    .frame(width: 72, height: 72)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 7) {
                    Text(readyTitle)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundColor(LocalVoiceTheme.primary)
                    Text(store.runtime.statusDetail)
                        .font(.system(size: 13))
                        .foregroundColor(LocalVoiceTheme.secondary)
                    HStack(spacing: 8) {
                        SmallTag(text: store.runtime.engineName)
                        SmallTag(text: store.runtime.modelName)
                    }
                }
            }

            Spacer(minLength: 18)

            HStack(spacing: 10) {
                QuietButton(title: "Copy last", symbol: "doc.on.doc", action: actions.copyLast)
                QuietButton(title: "Privacy test", symbol: "checkmark.shield", action: actions.runPrivacyTest)
            }
        }
        .padding(22)
        .frame(minHeight: 230)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LocalVoiceTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LocalVoiceTheme.line, lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch store.runtime.state {
        case .ready: return LocalVoiceTheme.accent
        case .listening: return LocalVoiceTheme.listening
        case .transcribing, .refining, .preparing: return LocalVoiceTheme.info
        case .error: return LocalVoiceTheme.danger
        }
    }

    private var readyTitle: String {
        if store.runtime.state == .listening {
            return "Listening now"
        }
        if !store.runtime.hotkeyReady {
            return "\(shortcutName) shortcut needs attention"
        }
        return "Hold \(shortcutName) to speak"
    }

    private var shortcutName: String {
        Config.load().hotkeySummary()
    }
}

private struct RuntimeCard: View {
    @ObservedObject var store: LocalVoiceStore
    let actions: LocalVoiceDashboardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SYSTEM HEALTH")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundColor(LocalVoiceTheme.muted)

            HealthRow(
                title: "Speech engine",
                detail: SpeechRouteDisplay.engineHealthDetail(
                    engineName: store.runtime.engineName,
                    selectedModel: store.runtime.modelName
                ),
                ready: store.runtime.whisperReady || store.runtime.parakeetReady
            )
            HealthRow(
                title: "Parakeet",
                detail: SpeechRouteDisplay.parakeetHealthDetail(
                    running: store.runtime.parakeetReady,
                    healthy: store.runtime.parakeetHealthy
                ),
                ready: store.runtime.parakeetReady && store.runtime.parakeetHealthy
            )
            HealthRow(
                title: "Microphone",
                detail: store.runtime.microphoneReady ? "Permission granted" : "Permission required",
                ready: store.runtime.microphoneReady
            )
            HealthRow(
                title: "\(shortcutName) shortcut",
                detail: hotkeyDetail,
                ready: store.runtime.hotkeyReady
            )
            HealthRow(
                title: "Privacy boundary",
                detail: store.runtime.privacyVerified ? "Local route verified" : "Run self-test",
                ready: store.runtime.privacyVerified
            )

            if let lastTake = store.runtime.lastTakeDetail {
                HealthRow(
                    title: "Last take",
                    detail: lastTake,
                    ready: store.runtime.lastTakeLandedInField
                )
            }

            if let repairDetail = store.runtime.permissionRepairDetail {
                Text(repairDetail)
                    .font(.system(size: 11))
                    .foregroundColor(LocalVoiceTheme.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                        .fill(LocalVoiceTheme.selected)
                    )
            }

            Spacer(minLength: 0)

            HStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                Text("Local process and loopback only")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(LocalVoiceTheme.muted)

            if !store.runtime.hotkeyReady
                || !store.runtime.microphoneReady {
                Button(
                    "Repair permissions",
                    action: actions.repairPermissions
                )
                .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LocalVoiceTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LocalVoiceTheme.line, lineWidth: 1)
        )
    }

    private var hotkeyDetail: String {
        if store.runtime.hotkeyReady {
            return "Listening for \(shortcutName)"
        }
        if !store.runtime.inputMonitoringReady {
            return "Input Monitoring required"
        }
        return "Monitor unavailable"
    }

    private var shortcutName: String {
        Config.load().hotkeySummary()
    }
}

private struct HistoryView: View {
    @ObservedObject var store: LocalVoiceStore
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                eyebrow: "LIBRARY",
                title: "History",
                subtitle: "Search, review, and reuse transcripts stored only on this Mac."
            )

            HStack {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(LocalVoiceTheme.muted)
                    TextField("Search transcripts or apps", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 13)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LocalVoiceTheme.panel)
                )
                Spacer()
                Text("\(filtered.count) records")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(LocalVoiceTheme.muted)
            }

            if filtered.isEmpty {
                EmptyState(
                    symbol: "text.magnifyingglass",
                    title: query.isEmpty ? "No history yet" : "No matching dictations",
                    detail: query.isEmpty ? "New local transcripts will collect here." : "Try a broader word or app name."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { record in
                            HistoryCard(record: record)
                        }
                    }
                }
            }
        }
        .padding(32)
        .background(LocalVoiceTheme.background)
    }

    private var filtered: [LocalVoiceRecord] {
        guard !query.isEmpty else { return store.records }
        return store.records.filter {
            $0.text.localizedCaseInsensitiveContains(query)
                || $0.applicationName.localizedCaseInsensitiveContains(query)
                || $0.modeName.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct ModesView: View {
    private let modes: [(String, String, String, String)] = [
        ("Quick message", "Slack, Messages", "Friendly, direct, light cleanup", "message.fill"),
        ("Professional", "Mail, Gmail", "Complete sentences and polished prose", "envelope.fill"),
        ("Technical", "Codex, VS Code", "Preserves paths, identifiers, and code terms", "chevron.left.forwardslash.chevron.right"),
        ("Command", "Terminal, iTerm", "Preserves flags and shell syntax", "terminal.fill"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "APP-AWARE WRITING",
                    title: "Modes",
                    subtitle: "Local Voice adapts formatting to the app you are already using."
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(modes, id: \.0) { mode in
                        ModeCard(title: mode.0, apps: mode.1, detail: mode.2, symbol: mode.3)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Routing rule", detail: "Deterministic before intelligent")
                    Text("The frontmost app selects a local prompt profile. Technical and terminal modes preserve symbols and identifiers. Cloud cleanup is never enabled silently.")
                        .font(.system(size: 13))
                        .foregroundColor(LocalVoiceTheme.secondary)
                        .lineSpacing(4)
                }
                .padding(20)
                .cardStyle()
            }
            .padding(32)
        }
    }
}

private struct DictionaryView: View {
    @State private var terms = VocabularyLearner.shared.manualTerms()
    @State private var newTerm = ""
    @State private var fromPhrase = ""
    @State private var toPhrase = ""
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(
                eyebrow: "PERSONAL LANGUAGE",
                title: "Dictionary",
                subtitle: "Add names, acronyms, and when-I-say → write-this rules. They apply on the next take. You can also say: remember that koon chan is Kun Chen."
            )

            HStack(spacing: 10) {
                TextField("Add a word or phrase (e.g. Kun Chen)", text: $newTerm)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LocalVoiceTheme.panel)
                    )
                    .onSubmit(addTerm)
                Button("Add", action: addTerm)
                    .buttonStyle(AccentButtonStyle())
            }

            HStack(spacing: 10) {
                TextField("When I say", text: $fromPhrase)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LocalVoiceTheme.panel)
                    )
                TextField("write", text: $toPhrase)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LocalVoiceTheme.panel)
                    )
                    .onSubmit(addReplacement)
                Button("Learn", action: addReplacement)
                    .buttonStyle(AccentButtonStyle())
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(LocalVoiceTheme.secondary)
            }

            HStack(spacing: 10) {
                Button("Clear auto-learned noise") {
                    let removed = VocabularyLearner.shared.purgeAutoLearned()
                    statusMessage = removed > 0
                        ? "Removed \(removed) auto-learned entries."
                        : "No auto-learned entries to remove."
                    refresh()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LocalVoiceTheme.muted)
            }

            if terms.isEmpty {
                EmptyState(
                    symbol: "text.badge.plus",
                    title: "No dictionary terms yet",
                    detail: "Manual entries stay on this Mac and take priority over auto-learned words."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(terms, id: \.self) { term in
                            HStack {
                                Text(term)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Button {
                                    _ = VocabularyLearner.shared.removeTerm(term)
                                    refresh()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(LocalVoiceTheme.muted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(LocalVoiceTheme.panel)
                            )
                        }
                    }
                }
            }
        }
        .padding(32)
        .onAppear(perform: refresh)
    }

    private func addTerm() {
        let candidate = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            statusMessage = "Enter a word or phrase first."
            return
        }
        guard VocabularyLearner.isValidManualTerm(candidate) else {
            statusMessage =
                "Could not add \"\(candidate)\". Use 1–60 characters with at least one letter."
            return
        }
        if VocabularyLearner.shared.manualTerms().contains(where: {
            $0.caseInsensitiveCompare(candidate) == .orderedSame
        }) {
            statusMessage = "\"\(candidate)\" is already in your dictionary."
            refresh()
            return
        }
        guard VocabularyLearner.shared.addTerm(candidate) else {
            statusMessage = "Could not add \"\(candidate)\". Try again."
            return
        }
        newTerm = ""
        statusMessage = "Added \"\(candidate)\"."
        refresh()
    }

    private func addReplacement() {
        let from = fromPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else {
            statusMessage = "Enter both what you say and what to write."
            return
        }
        guard VocabularyLearner.shared.addReplacement(from: from, to: to) else {
            statusMessage = "Could not learn that pair. Common English cannot be a source."
            return
        }
        fromPhrase = ""
        toPhrase = ""
        statusMessage = "Learned \"\(from)\" → \"\(to)\"."
        refresh()
    }

    private func refresh() {
        terms = VocabularyLearner.shared.manualTerms()
    }
}

private struct ModelsView: View {
    @ObservedObject var store: LocalVoiceStore

    private let featuredModels: [(String, String, String)] = [
        ("Parakeet TDT v3", "Fast multilingual", "bolt.fill"),
        ("Whisper large-v3-turbo", "High-accuracy multilingual", "scope"),
        ("Whisper base.en", "Lightweight English", "leaf.fill"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "LOCAL INFERENCE",
                    title: "Models",
                    subtitle: "Choose speed or accuracy without sending audio to a hosted API."
                )

                HStack(spacing: 14) {
                    ForEach(featuredModels, id: \.0) { model in
                        ModelCard(
                            title: model.0,
                            detail: model.1,
                            symbol: model.2,
                            active: SpeechRouteDisplay.isFeaturedCardActive(
                                title: model.0,
                                engineName: store.runtime.engineName,
                                selectedModel: store.runtime.modelName
                            )
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "Current route",
                        detail: store.runtime.parakeetReady ? "Parakeet running · Whisper fallback ready" : "Automatic fallback"
                    )
                    Text(
                        SpeechRouteDisplay.engineHealthDetail(
                            engineName: store.runtime.engineName,
                            selectedModel: store.runtime.modelName
                        )
                    )
                    .font(.system(size: 13))
                    .foregroundColor(LocalVoiceTheme.secondary)
                    RouteStep(index: "01", title: "Fast path", detail: "Parakeet when installed and compatible")
                    RouteStep(index: "02", title: "Quality path", detail: "Warm whisper-server with your selected model")
                    RouteStep(index: "03", title: "Recovery path", detail: "whisper-cli if the persistent engine is unavailable")
                }
                .padding(20)
                .cardStyle()
            }
            .padding(32)
        }
    }
}

private struct PrivacyView: View {
    @ObservedObject var store: LocalVoiceStore
    let actions: LocalVoiceDashboardActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "TRUST CENTER",
                    title: "Privacy",
                    subtitle: "The default speech path is local. Any future network route must be explicit."
                )

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: store.runtime.privacyVerified ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                            .font(.system(size: 34))
                            .foregroundColor(store.runtime.privacyVerified ? LocalVoiceTheme.accent : LocalVoiceTheme.warning)
                        Text(store.runtime.privacyVerified ? "Local speech route verified" : "Verification available")
                            .font(.system(size: 20, weight: .semibold))
                        Text("The self-test confirms a configured local engine and successful transcription through a local process or loopback route. Packet isolation is checked separately during release testing.")
                            .font(.system(size: 13))
                            .foregroundColor(LocalVoiceTheme.secondary)
                            .lineSpacing(4)
                        Button("Run privacy self-test", action: actions.runPrivacyTest)
                            .buttonStyle(AccentButtonStyle())
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    VStack(spacing: 0) {
                        PrivacyRule(title: "Audio retention", detail: "Off by default", ready: true)
                        Divider().overlay(LocalVoiceTheme.line)
                        PrivacyRule(title: "Transcript history", detail: "Local JSON, 30-day default", ready: true)
                        Divider().overlay(LocalVoiceTheme.line)
                        PrivacyRule(title: "Speech API", detail: "Loopback only", ready: true)
                        Divider().overlay(LocalVoiceTheme.line)
                        PrivacyRule(title: "File preparation", detail: "Temporary audio deleted", ready: true)
                        Divider().overlay(LocalVoiceTheme.line)
                        PrivacyRule(title: "Telemetry", detail: "None", ready: true)
                    }
                    .frame(width: 330)
                    .cardStyle()
                }

                PrivacySweepPanel()
            }
            .padding(32)
        }
    }
}

private struct PrivacySweepPanel: View {
    @ObservedObject private var caseStore: PrivacyCaseStore
    @State private var fullName = ""
    @State private var emailOrPhone = ""
    @State private var location = ""
    @State private var searches: [PrivacySweepSearch] = []
    @State private var findingLabel = ""
    @State private var findingURL = ""
    @State private var feedback: String?

    init(caseStore: PrivacyCaseStore = .shared) {
        self.caseStore = caseStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LocalVoiceTheme.accent.opacity(0.12))
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(LocalVoiceTheme.accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Privacy Sweep")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Find likely people-search exposures, verify each match yourself, and track removal work locally.")
                        .font(.system(size: 12.5))
                        .foregroundColor(LocalVoiceTheme.secondary)
                }

                Spacer()

                Text("PREVIEW ONLY · LOCAL CASES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(LocalVoiceTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(LocalVoiceTheme.accent.opacity(0.1))
                    )
            }

            Text("Search details stay in memory and are not saved by Local Voice. Opening a result sends that query to the search provider; nothing is scanned or submitted in the background.")
                .font(.system(size: 11.5))
                .foregroundColor(LocalVoiceTheme.muted)
                .lineSpacing(3)

            HStack(spacing: 10) {
                SweepField(title: "Full legal name", text: $fullName)
                SweepField(title: "Email or phone (optional)", text: $emailOrPhone)
                SweepField(title: "City and state (optional)", text: $location)
            }

            HStack(spacing: 10) {
                Button("Build exposure search", action: buildSearches)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Open California DROP") {
                    NSWorkspace.shared.open(PrivacySweepPlanner.californiaDROPURL)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(LocalVoiceTheme.secondary)
                .padding(.horizontal, 15)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LocalVoiceTheme.panel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(LocalVoiceTheme.line, lineWidth: 1)
                )

                Spacer()
            }

            if !searches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searches) { search in
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(LocalVoiceTheme.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(search.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(search.detail)
                                    .font(.system(size: 11))
                                    .foregroundColor(LocalVoiceTheme.muted)
                            }
                            Spacer()
                            Button("Open") {
                                NSWorkspace.shared.open(search.url)
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(LocalVoiceTheme.accent)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 54)

                        if search.id != searches.last?.id {
                            Divider().overlay(LocalVoiceTheme.line)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LocalVoiceTheme.panel.opacity(0.72))
                )
            }

            Divider().overlay(LocalVoiceTheme.line)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Removal tracker",
                    detail: "\(caseStore.cases.count) versioned cases saved locally"
                )

                if let next = PrivacySchedule.queue(
                    cases: caseStore.cases
                ).first {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(LocalVoiceTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next privacy action")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(LocalVoiceTheme.secondary)
                            Text(next.action)
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        Spacer()
                        Text(next.dueAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(
                                next.urgency == .upcoming
                                    ? LocalVoiceTheme.muted
                                    : LocalVoiceTheme.warning
                            )
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LocalVoiceTheme.panel.opacity(0.72))
                    )
                }

                HStack(spacing: 10) {
                    SweepField(title: "Source label (optional)", text: $findingLabel)
                    SweepField(title: "Exact exposure URL", text: $findingURL)
                    Button("Save finding", action: saveFinding)
                        .buttonStyle(AccentButtonStyle())
                        .disabled(findingURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let message = feedback ?? caseStore.lastError {
                    Text(message)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(
                            caseStore.lastError == nil
                                ? LocalVoiceTheme.accent
                                : LocalVoiceTheme.warning
                        )
                }

                if caseStore.cases.isEmpty {
                    Text("Confirm a result belongs to you, then paste its exact page here. Local Voice creates a local case and never submits a removal request automatically.")
                        .font(.system(size: 11.5))
                        .foregroundColor(LocalVoiceTheme.muted)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(caseStore.cases) { removalCase in
                            PrivacyCaseRow(
                                removalCase: removalCase,
                                transition: {
                                    caseStore.transition(
                                        id: removalCase.id,
                                        to: $0
                                    )
                                },
                                copyDraft: {
                                    copyRemovalDraft(for: removalCase)
                                }
                            )
                            if removalCase.id != caseStore.cases.last?.id {
                                Divider().overlay(LocalVoiceTheme.line)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LocalVoiceTheme.panel.opacity(0.72))
                    )
                }
            }
        }
        .padding(22)
        .cardStyle()
    }

    private func buildSearches() {
        searches = PrivacySweepPlanner.searches(
            fullName: fullName,
            emailOrPhone: emailOrPhone,
            location: location
        )
        feedback = nil
    }

    private func saveFinding() {
        guard caseStore.addCase(label: findingLabel, urlString: findingURL) else {
            feedback = nil
            return
        }
        findingLabel = ""
        findingURL = ""
        feedback = "Finding saved only on this Mac."
    }

    private func copyRemovalDraft(for removalCase: PrivacyRemovalCase) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            caseStore.removalDraft(for: removalCase),
            forType: .string
        )
        if removalCase.state == .identityConfirmed {
            caseStore.transition(id: removalCase.id, to: .draftReady)
        }
        feedback = "Deletion-request draft copied. Review it before sending."
    }
}

private struct SweepField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LocalVoiceTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(LocalVoiceTheme.line, lineWidth: 1)
            )
    }
}

private struct PrivacyCaseRow: View {
    let removalCase: PrivacyRemovalCase
    let transition: (PrivacyCaseState) -> Void
    let copyDraft: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(
                systemName: removalCase.state == .removed
                    ? "checkmark.seal.fill"
                    : "shield.lefthalf.filled"
            )
                .foregroundColor(
                    removalCase.state == .removed
                        ? LocalVoiceTheme.accent
                        : LocalVoiceTheme.secondary
                )
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(removalCase.label)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(
                    [
                        removalCase.exposureURL.host
                            ?? removalCase.exposureURL.absoluteString,
                        "\(removalCase.events.count) timeline events",
                    ]
                    .joined(separator: " · ")
                )
                    .font(.system(size: 11))
                    .foregroundColor(LocalVoiceTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            Button("Open") {
                NSWorkspace.shared.open(removalCase.exposureURL)
            }
            .buttonStyle(.borderless)

            if let brokerID = removalCase.brokerID,
               let broker = PrivacyBrokerRegistry.broker(id: brokerID) {
                Button("Official opt-out") {
                    NSWorkspace.shared.open(broker.optOutURL)
                }
                .buttonStyle(.borderless)
                .help(
                    "Verified \(broker.workflowVerifiedAt.formatted(date: .abbreviated, time: .omitted)); requires \(broker.verificationMethods.map { $0.label }.joined(separator: ", "))"
                )
            }

            Button("Copy draft", action: copyDraft)
                .buttonStyle(.borderless)
                .disabled(
                    ![.identityConfirmed, .draftReady, .awaitingUserSubmission]
                        .contains(removalCase.state)
                )

            Menu(removalCase.state.label) {
                ForEach(
                    PrivacyWorkflow.allowedTransitions(from: removalCase.state)
                        .filter { $0 != .removed },
                    id: \.self
                ) { state in
                    Button(state.label) {
                        transition(state)
                    }
                }
                if PrivacyWorkflow.allowedTransitions(
                    from: removalCase.state
                ).contains(.removed) {
                    Text("Removal needs confirmation evidence")
                }
            }
            .frame(width: 150)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
    }
}

private struct SettingsView: View {
    let actions: LocalVoiceDashboardActions
    @State private var config = Config.load()
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "PREFERENCES",
                    title: "Settings",
                    subtitle: "The defaults are intentionally private, fast, and low-friction."
                )

                VStack(spacing: 0) {
                    SettingToggle(
                        title: "Launch at login",
                        detail: "Keep the \(config.hotkeySummary()) shortcut available after you sign in",
                        value: Binding(
                            get: { launchAtLogin },
                            set: { setLaunchAtLogin($0) }
                        )
                    )
                    SettingDivider()
                    SettingToggle(
                        title: "Keep model warm",
                        detail: "Avoid model load time between dictations",
                        value: Binding(
                            get: { config.keepModelWarm?.value ?? true },
                            set: { value in update { $0.keepModelWarm = FlexBool(value) } }
                        )
                    )
                    SettingDivider()
                    SettingToggle(
                        title: "Live transcription preview",
                        detail: "Show partial words in the floating pill",
                        value: Binding(
                            get: { config.streamingEnabled?.value ?? true },
                            set: { value in update { $0.streamingEnabled = FlexBool(value) } }
                        )
                    )
                    SettingDivider()
                    SettingToggle(
                        title: "Save transcript history",
                        detail: "Keep dictation and file transcripts locally; audio remains off by default",
                        value: Binding(
                            get: { config.saveTranscriptHistory?.value ?? true },
                            set: { value in update { $0.saveTranscriptHistory = FlexBool(value) } }
                        )
                    )
                    SettingDivider()
                    SettingToggle(
                        title: "Local refinement",
                        detail: "Optional Ollama rewrite. Leave off for the fastest insertion.",
                        value: Binding(
                            get: { config.ollamaEnabled?.value ?? false },
                            set: { value in update { $0.ollamaEnabled = FlexBool(value) } }
                        )
                    )
                }
                .cardStyle()

                if let launchAtLoginError {
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(LocalVoiceTheme.warning)
                        Text(launchAtLoginError)
                            .font(.system(size: 12))
                            .foregroundColor(LocalVoiceTheme.secondary)
                    }
                    .padding(14)
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Recording shortcut", detail: "Click, then press a key")
                    ShortcutRecorderField(
                        hotkey: config.hotkey,
                        captureStateChanged: actions.shortcutCaptureChanged,
                        commit: setShortcut
                    )
                    Text(shortcutGuidance)
                        .font(.system(size: 13))
                        .foregroundColor(LocalVoiceTheme.secondary)
                    HStack(spacing: 10) {
                        QuietButton(title: "Open advanced config", symbol: "doc.text", action: actions.openConfiguration)
                        QuietButton(title: "Reload", symbol: "arrow.clockwise", action: actions.reloadConfiguration)
                    }
                }
                .padding(20)
                .cardStyle()
            }
            .padding(32)
        }
    }

    private func update(_ transform: (inout Config) -> Void) {
        transform(&config)
        try? config.save()
        actions.reloadConfiguration()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginManager.isEnabled
            launchAtLoginError = LaunchAtLoginManager.statusSummary == "requires approval"
                ? "Approve Local Voice in System Settings → General → Login Items."
                : nil
        } catch {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            launchAtLoginError =
                "Launch at login could not be updated: \(error.localizedDescription)"
        }
    }

    private func setShortcut(_ hotkey: HotkeyConfig) -> String? {
        if let error = actions.setShortcut(hotkey) {
            return error
        }
        config.hotkey = hotkey
        return nil
    }

    private var shortcutGuidance: String {
        if config.hotkey.keyCode == 63 {
            return "Hold to speak. Double-tap fn to lock a longer recording, then tap again to finish."
        }
        return "Hold \(config.hotkeySummary()) to speak, then release to finish."
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(LocalVoiceTheme.accent)
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundColor(LocalVoiceTheme.primary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(LocalVoiceTheme.secondary)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(LocalVoiceTheme.muted)
        }
    }
}

private struct MetricCard: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(LocalVoiceTheme.muted)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LocalVoiceTheme.accent)
            }
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(LocalVoiceTheme.secondary)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LocalVoiceTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LocalVoiceTheme.line, lineWidth: 1)
        )
    }
}

private struct HealthRow: View {
    let title: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill((ready ? LocalVoiceTheme.accent : LocalVoiceTheme.warning).opacity(0.12))
                Image(systemName: ready ? "checkmark" : "exclamationmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ready ? LocalVoiceTheme.accent : LocalVoiceTheme.warning)
            }
            .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundColor(LocalVoiceTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RecordRow: View {
    let record: LocalVoiceRecord

    var body: some View {
        HStack(spacing: 14) {
            AppGlyph(name: record.applicationName)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(LocalVoiceTheme.primary)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(record.applicationName)
                    Text("•")
                    Text(record.modeName)
                    Text("•")
                    Text(record.createdAt, style: .relative)
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

private struct HistoryCard: View {
    let record: LocalVoiceRecord
    @State private var copied = false
    @State private var copiedContract = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                HStack(spacing: 10) {
                    AppGlyph(name: record.applicationName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.applicationName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10.5))
                            .foregroundColor(LocalVoiceTheme.muted)
                    }
                }
                Spacer()
                SmallTag(text: record.modeName)
                if let contractJSON = record.contractJSON {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            contractJSON,
                            forType: .string
                        )
                        copiedContract = true
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 1.5
                        ) {
                            copiedContract = false
                        }
                    } label: {
                        Image(
                            systemName: copiedContract
                                ? "checkmark"
                                : "curlybraces"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(
                            copiedContract
                                ? LocalVoiceTheme.accent
                                : LocalVoiceTheme.secondary
                        )
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(LocalVoiceTheme.raised))
                    }
                    .buttonStyle(.plain)
                    .help("Copy canonical voice contract receipt")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.text, forType: .string)
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
                .help("Copy transcript")
            }

            Text(record.text)
                .font(.system(size: 13))
                .foregroundColor(LocalVoiceTheme.primary)
                .lineSpacing(4)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Text(record.engineName)
                Text("•")
                if record.contractPair != nil {
                    Text("Contract v1")
                    Text("•")
                }
                Text("\(record.wordCount) words")
                Text("•")
                Text(formatLatency(record.finishMilliseconds))
            }
            .font(.system(size: 10.5))
            .foregroundColor(LocalVoiceTheme.muted)
        }
        .padding(17)
        .cardStyle()
    }
}

private struct AppGlyph: View {
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LocalVoiceTheme.raised)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(LocalVoiceTheme.accent)
        }
        .frame(width: 36, height: 36)
    }
}

private struct ModeCard: View {
    let title: String
    let apps: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LocalVoiceTheme.accent.opacity(0.1))
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LocalVoiceTheme.accent)
                }
                .frame(width: 38, height: 38)
                Spacer()
                Text("AUTO")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(LocalVoiceTheme.accent)
            }
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(apps)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(LocalVoiceTheme.accent)
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(LocalVoiceTheme.secondary)
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 165, alignment: .topLeading)
        .cardStyle()
    }
}

private struct ModelCard: View {
    let title: String
    let detail: String
    let symbol: String
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(LocalVoiceTheme.accent)
                Spacer()
                if active {
                    StatusPill(title: "ACTIVE", color: LocalVoiceTheme.accent)
                }
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(LocalVoiceTheme.secondary)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .cardStyle()
    }
}

private struct RouteStep: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 13) {
            Text(index)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(LocalVoiceTheme.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(LocalVoiceTheme.accent.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(LocalVoiceTheme.muted)
            }
        }
    }
}

private struct PrivacyRule: View {
    let title: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundColor(LocalVoiceTheme.muted)
            }
            Spacer()
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(ready ? LocalVoiceTheme.accent : LocalVoiceTheme.warning)
        }
        .padding(.horizontal, 17)
        .frame(height: 64)
    }
}

private struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var value: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(LocalVoiceTheme.muted)
            }
            Spacer()
            Toggle("", isOn: $value)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(LocalVoiceTheme.accent)
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
    }
}

private struct SettingDivider: View {
    var body: some View {
        Rectangle()
            .fill(LocalVoiceTheme.line)
            .frame(height: 1)
            .padding(.leading, 18)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundColor(LocalVoiceTheme.accent)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundColor(LocalVoiceTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .cardStyle()
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
        }
        .foregroundColor(color)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(color.opacity(0.1)))
    }
}

struct SmallTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(LocalVoiceTheme.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(Capsule().fill(LocalVoiceTheme.raised))
    }
}

struct QuietButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(LocalVoiceTheme.secondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LocalVoiceTheme.raised)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(LocalVoiceTheme.background)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LocalVoiceTheme.accent.opacity(configuration.isPressed ? 0.78 : 1))
            )
    }
}

extension View {
    func cardStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LocalVoiceTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LocalVoiceTheme.line, lineWidth: 1)
        )
    }
}

enum LocalVoiceTheme {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let sidebar = Color(red: 0.054, green: 0.063, blue: 0.076)
    static let panel = Color(red: 0.075, green: 0.086, blue: 0.102)
    static let raised = Color(red: 0.102, green: 0.114, blue: 0.133)
    static let selected = Color(red: 0.102, green: 0.122, blue: 0.139)
    static let line = Color.white.opacity(0.075)
    static let primary = Color(red: 0.94, green: 0.95, blue: 0.96)
    static let secondary = Color(red: 0.66, green: 0.69, blue: 0.73)
    static let muted = Color(red: 0.43, green: 0.47, blue: 0.52)
    static let accent = Color(red: 0.42, green: 0.84, blue: 0.64)
    static let info = Color(red: 0.40, green: 0.66, blue: 0.96)
    static let listening = Color(red: 0.96, green: 0.45, blue: 0.40)
    static let warning = Color(red: 0.96, green: 0.69, blue: 0.31)
    static let danger = Color(red: 0.96, green: 0.39, blue: 0.42)
}

func formatLatency(_ value: Double?) -> String {
    guard let value, value > 0 else { return "—" }
    if value < 1_000 { return "\(Int(value.rounded())) ms" }
    return String(format: "%.1f s", value / 1_000)
}

private func formatMinutes(_ value: Double) -> String {
    if value < 1 { return "\(Int((value * 60).rounded())) sec" }
    return String(format: "%.1f min", value)
}
