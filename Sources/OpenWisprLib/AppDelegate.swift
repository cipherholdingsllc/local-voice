import AppKit
import AVFoundation

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManagers: [CGEventHotkeyManager] = []
    var recorder: AudioRecorder!
    var sttRouter: STTRouter!
    var inserter: TextInserter!
    var config: Config!
    var pillOverlay = PillOverlay()
    var ollamaCleanup: OllamaCleanup!
    var isPressed = false
    var isReady = false
    private var isLockMode = false
    public var lastTranscription: String?
    private var streamingPartial = ""
    private let streamingQueue = DispatchQueue(label: "local-voice.streaming", qos: .userInitiated)
    private var dashboardCaptureMode = false
    private var captureApplicationName = "Unknown app"
    private var captureBundleIdentifier: String?
    private var captureModeName = "Default"
    private var captureRequestID = UUID()
    private var captureProfileID = VoiceContractProfileID.generalDefault
    private var permissionTimer: Timer?
    private var lastPermissionSnapshot: LocalVoicePermissionSnapshot?
    private var hotkeyMonitorReady = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        recorder = AudioRecorder()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setup()
        }
    }

    private func setup() {
        do {
            try setupInner()
        } catch {
            print("Fatal setup error: \(error.localizedDescription)")
        }
    }

    private func setupInner() throws {
        config = Config.load()
        inserter = TextInserter()
        migrateAudioDeviceUIDIfNeeded()
        recorder.preferredDeviceID = AudioDeviceManager.resolveConfiguredDeviceID(
            uid: config.audioInputDeviceUID,
            legacyID: config.audioInputDeviceID
        )
        if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
            RecordingStore.deleteAllRecordings()
        }
        rebuildSTTRouter()
        ollamaCleanup = OllamaCleanup(
            model: config.ollamaModel ?? "llama3.2:latest",
            enabled: config.ollamaEnabled?.value ?? true
        )

        DispatchQueue.main.async {
            self.statusBar.reprocessHandler = { [weak self] url in
                self?.reprocess(audioURL: url)
            }
            self.statusBar.onConfigChange = { [weak self] newConfig in
                self?.applyConfigChange(newConfig)
            }
            self.statusBar.onPrivacyTest = { [weak self] in
                self?.runPrivacySelfTest()
            }
            self.statusBar.onShowLatency = {
                LatencyPanelController.shared.show()
            }
            self.statusBar.onToggleRawPolished = { [weak self] in
                self?.toggleRawPolished()
            }
            self.statusBar.onOpenDashboard = { [weak self] in
                self?.showDashboard()
            }
            self.statusBar.onRepairPermissions = { [weak self] in
                self?.repairPermissions()
            }
            self.statusBar.buildMenu()
        }

        if Transcriber.findWhisperBinary() == nil {
            print("Error: whisper-cpp not found. Install it with: brew install whisper-cpp")
            return
        }

        Permissions.ensureMicrophone()

        if !AXIsProcessTrusted() {
            print("Accessibility: not granted")
            Permissions.promptAccessibility()
        } else {
            print("Accessibility: granted")
        }

        if !Transcriber.modelExists(modelSize: config.modelSize) {
            DispatchQueue.main.async {
                self.statusBar.state = .downloading
                self.statusBar.updateDownloadProgress("Downloading \(self.config.modelSize) model...")
            }
            print("Downloading \(config.modelSize) model...")
            try ModelDownloader.download(modelSize: config.modelSize) { [weak self] percent in
                DispatchQueue.main.async {
                    let pct = Int(percent)
                    self?.statusBar.updateDownloadProgress("Downloading \(self?.config.modelSize ?? "") model... \(pct)%", percent: percent)
                }
            }
            DispatchQueue.main.async {
                self.statusBar.updateDownloadProgress(nil)
            }
        }

        if let modelPath = Transcriber.findModel(modelSize: config.modelSize) {
            let modelURL = URL(fileURLWithPath: modelPath)
            if !ModelDownloader.isValidGGMLFile(at: modelURL) {
                let msg = "Model file is corrupted. Re-download with: local-voice download-model \(config.modelSize)"
                print("Error: \(msg)")
                DispatchQueue.main.async {
                    self.statusBar.state = .error(msg)
                    self.statusBar.buildMenu()
                }
                return
            }
        }

        recorder.prewarm()

        pillOverlay.configure(anchor: .bottomRight, followsCursor: false)

        if config.keepModelWarm?.value ?? true {
            sttRouter.warmup()
        }

        _ = Permissions.requestInputMonitoring(openSettings: false)

        let privacy = PrivacySelfTest.run(router: sttRouter)
        if config.showPrivacyBadge?.value ?? true {
            print("Privacy self-test: \(privacy.message)")
        }
        DispatchQueue.main.async {
            LocalVoiceStore.shared.updateRuntime {
                $0.privacyVerified = privacy.passed
                $0.whisperReady = Transcriber.findWhisperBinary() != nil
                $0.accessibilityReady = AXIsProcessTrusted()
                $0.microphoneReady = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                $0.inputMonitoringReady = CGPreflightListenEventAccess()
                $0.hotkeyReady = false
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.startListening()
            self?.startPermissionMonitoring()
            OnboardingWizard.showIfNeeded()
        }
    }

    private func rebuildSTTRouter() {
        let vocab = VocabularyLearner.shared.merged(with: config.customVocabulary ?? [])
        sttRouter = STTRouter(
            language: config.language,
            modelSize: config.modelSize,
            preferredEngine: config.sttEngine ?? .auto,
            spokenPunctuation: config.spokenPunctuation?.value ?? false,
            initialPrompt: vocab.joined(separator: ", ")
        )
    }

    func runPrivacySelfTest() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = PrivacySelfTest.run(router: self.sttRouter)
            DispatchQueue.main.async {
                self.statusBar.state = result.passed ? .idle : .error(result.message)
                self.statusBar.privacyStatus = result.message
                self.statusBar.buildMenu()
                LocalVoiceStore.shared.updateRuntime {
                    $0.privacyVerified = result.passed
                    $0.statusDetail = result.message
                    $0.state = result.passed ? .ready : .error
                }
            }
        }
    }

    func showDashboard() {
        DashboardWindowController.shared.show(
            store: .shared,
            actions: LocalVoiceDashboardActions(
                toggleRecording: { [weak self] in self?.toggleDashboardCapture() },
                copyLast: { [weak self] in self?.copyLastTranscription() },
                runPrivacyTest: { [weak self] in self?.runPrivacySelfTest() },
                reloadConfiguration: { [weak self] in self?.reloadConfig() },
                openConfiguration: {
                    if !FileManager.default.fileExists(atPath: Config.configFile.path) {
                        try? Config.defaultConfig.save()
                    }
                    NSWorkspace.shared.open(Config.configFile)
                },
                repairPermissions: { [weak self] in
                    self?.repairPermissions()
                }
            )
        )
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        guard isReady else { return }
        refreshPermissionState()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        for manager in hotkeyManagers { manager.stop() }
        hotkeyManagers = []
        sttRouter?.shutdown(preserveParakeet: false)
    }

    private func toggleDashboardCapture() {
        if isPressed {
            handleRecordingStop()
        } else {
            dashboardCaptureMode = true
            handleRecordingStart()
        }
    }

    private func copyLastTranscription() {
        guard let lastTranscription else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscription, forType: .string)
    }

    func toggleRawPolished() {
        let text = TranscriptStore.shared.toggle()
        inserter.insert(text: text)
    }

    private func startListening() {
        for m in hotkeyManagers { m.stop() }
        hotkeyManagers = []
        hotkeyMonitorReady = false

        let permissions = Permissions.snapshot()
        let globalToggle = config.toggleMode?.value ?? false
        if permissions.inputMonitoring {
            for hk in config.hotkeys {
                let mode = hk.resolvedActivationMode(globalToggle: globalToggle)
                let manager = CGEventHotkeyManager(
                    keyCode: hk.keyCode,
                    modifiers: hk.modifierFlags,
                    activationMode: mode
                )
                manager.onLockChanged = { [weak self] locked in
                    self?.isLockMode = locked
                    DispatchQueue.main.async {
                        if locked {
                            self?.pillOverlay.show(state: .locked)
                        }
                    }
                }
                let started = manager.start(
                    onKeyDown: { [weak self] in
                        self?.handleKeyDown()
                    },
                    onKeyUp: { [weak self] in
                        self?.handleKeyUp()
                    }
                )
                if started {
                    hotkeyManagers.append(manager)
                }
            }
        }
        hotkeyMonitorReady =
            !config.hotkeys.isEmpty
            && hotkeyManagers.count == config.hotkeys.count

        isReady = true
        statusBar.sttEngineName = sttRouter.activeEngineName()
        let languageName = Config.supportedLanguages
            .first(where: { $0.code == config.language })?.name ?? config.language
        LocalVoiceStore.shared.updateRuntime {
            $0.engineName = self.sttRouter.activeEngineName()
            $0.modelName = self.config.modelSize
            $0.languageName = languageName
            $0.whisperReady = Transcriber.findWhisperBinary() != nil
        }
        applyPermissionSnapshot(permissions)

        let hotkeyDesc = config.hotkeySummary()
        print("Local Voice v\(OpenWispr.version)")
        if config.showPrivacyBadge?.value ?? true {
            print("Privacy: local speech process or loopback route; no hosted STT configured")
        }
        print("Hotkey: \(hotkeyDesc)")
        print("STT: \(sttRouter.activeEngineName())")
        print("Model: \(config.modelSize)")
        if hotkeyMonitorReady {
            print("Hotkey monitor: active")
        } else {
            print("Hotkey monitor: unavailable")
        }
        print(permissions.dictationReady && hotkeyMonitorReady ? "Ready." : "Needs permission.")
    }

    private func startPermissionMonitoring() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            self?.refreshPermissionState()
        }
        if let permissionTimer {
            RunLoop.main.add(permissionTimer, forMode: .common)
        }
        refreshPermissionState()
    }

    private func refreshPermissionState() {
        guard isReady else { return }
        let snapshot = Permissions.snapshot()
        if snapshot.inputMonitoring != lastPermissionSnapshot?.inputMonitoring {
            startListening()
            return
        }
        if snapshot != lastPermissionSnapshot {
            applyPermissionSnapshot(snapshot)
        }
    }

    private func applyPermissionSnapshot(
        _ snapshot: LocalVoicePermissionSnapshot
    ) {
        lastPermissionSnapshot = snapshot
        LocalVoiceStore.shared.updateRuntime {
            $0.accessibilityReady = snapshot.accessibility
            $0.microphoneReady = snapshot.microphone
            $0.inputMonitoringReady = snapshot.inputMonitoring
            $0.hotkeyReady = self.hotkeyMonitorReady
            if snapshot.dictationReady && self.hotkeyMonitorReady {
                $0.state = .ready
                $0.statusDetail =
                    "Hold \(self.config.hotkeySummary()) to dictate anywhere"
            } else {
                $0.state = .error
                $0.statusDetail =
                    snapshot.blockingSummary
                    ?? "The fn hotkey monitor could not start"
            }
        }

        guard !isPressed else { return }
        if snapshot.dictationReady && hotkeyMonitorReady {
            statusBar.state = .idle
        } else {
            statusBar.permissionDetail =
                snapshot.blockingSummary
                ?? "The fn hotkey monitor could not start"
            statusBar.state = .waitingForPermission
        }
        statusBar.buildMenu()
    }

    func repairPermissions() {
        let snapshot = Permissions.snapshot()
        if !snapshot.inputMonitoring {
            _ = Permissions.requestInputMonitoring(openSettings: true)
        } else if !snapshot.microphone {
            Permissions.ensureMicrophone()
            if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                Permissions.openMicrophoneSettings()
            }
        } else if !snapshot.accessibility {
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
        } else {
            startListening()
        }
        showDashboard()
        refreshPermissionState()
    }

    public func reloadConfig() {
        let newConfig = Config.load()
        applyConfigChange(newConfig)
    }

    /// Configs written by older versions store only the numeric AudioDeviceID,
    /// which is not stable across reboots or device replugs. If that ID still
    /// refers to a device, persist its UID so the selection survives.
    private func migrateAudioDeviceUIDIfNeeded() {
        guard config.audioInputDeviceUID == nil,
              let legacyID = config.audioInputDeviceID,
              let uid = AudioDeviceManager.getDeviceUID(deviceID: legacyID) else { return }
        config.audioInputDeviceUID = uid
        try? config.save()
    }

    func applyConfigChange(_ newConfig: Config) {
        guard isReady else { return }
        let wasDownloading: Bool
        if case .downloading = statusBar.state { wasDownloading = true } else { wasDownloading = false }
        let newDeviceID = AudioDeviceManager.resolveConfiguredDeviceID(
            uid: newConfig.audioInputDeviceUID,
            legacyID: newConfig.audioInputDeviceID
        )
        let deviceChanged = recorder.preferredDeviceID != newDeviceID
        config = newConfig
        let saveHistory =
            config.saveTranscriptHistory?.value ?? true
        LocalVoiceStore.shared.setPersistenceEnabled(saveHistory)
        FileTranscriptionStore.shared.setPersistenceEnabled(saveHistory)
        recorder.preferredDeviceID = newDeviceID
        if deviceChanged {
            recorder.reload()
        }
        rebuildSTTRouter()
        ollamaCleanup = OllamaCleanup(
            model: config.ollamaModel ?? "llama3.2:latest",
            enabled: config.ollamaEnabled?.value ?? true
        )
        inserter = TextInserter()

        startListening()

        if !wasDownloading && !Transcriber.modelExists(modelSize: config.modelSize) {
            statusBar.state = .downloading
            statusBar.updateDownloadProgress("Downloading \(config.modelSize) model...")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try ModelDownloader.download(modelSize: newConfig.modelSize) { percent in
                        DispatchQueue.main.async {
                            let pct = Int(percent)
                            self?.statusBar.updateDownloadProgress("Downloading \(newConfig.modelSize) model... \(pct)%", percent: percent)
                        }
                    }
                    DispatchQueue.main.async {
                        self?.statusBar.state = .idle
                        self?.statusBar.updateDownloadProgress(nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        print("Error downloading model: \(error.localizedDescription)")
                        self?.statusBar.state = .idle
                        self?.statusBar.updateDownloadProgress(nil)
                    }
                }
            }
        }

        statusBar.buildMenu()

        let hotkeyDesc = config.hotkeySummary()
        print("Config updated: lang=\(config.language) model=\(config.modelSize) hotkey=\(hotkeyDesc)")
    }

    private func handleKeyDown() {
        guard isReady else { return }

        let isToggle = config.toggleMode?.value ?? false

        if isToggle {
            if isPressed {
                handleRecordingStop()
            } else {
                handleRecordingStart()
            }
        } else {
            guard !isPressed else { return }
            handleRecordingStart()
        }
    }

    private func handleKeyUp() {
        let isToggle = config.toggleMode?.value ?? false
        if isToggle { return }
        if isLockMode { return }

        handleRecordingStop()
    }

    private func handleRecordingStart() {
        guard !isPressed else { return }
        isPressed = true
        let frontmost = NSWorkspace.shared.frontmostApplication
        captureApplicationName = dashboardCaptureMode
            ? "Local Voice"
            : (frontmost?.localizedName ?? "Unknown app")
        captureBundleIdentifier = dashboardCaptureMode
            ? "com.cipherholdings.localvoice"
            : frontmost?.bundleIdentifier
        captureModeName = AppPromptProfiles.profile(for: captureBundleIdentifier).name
        captureRequestID = UUID()
        captureProfileID = VoiceContractProfileID.localVoiceProfile(
            bundleIdentifier: captureBundleIdentifier,
            modeName: captureModeName
        )
        streamingPartial = ""
        LatencyInstrumentation.shared.reset()
        LatencyInstrumentation.shared.mark("record")

        statusBar.state = .recording
        LocalVoiceStore.shared.setState(.listening, detail: "Speak naturally. Click stop when finished.")
        if config.showCursorHUD?.value ?? true {
            pillOverlay.show(state: .listening)
        }

        recorder.onLevel = { [weak self] level in
            self?.pillOverlay.updateLevel(level)
        }

        let streamingOn = config.streamingEnabled?.value ?? true
        if streamingOn {
            recorder.onChunkReady = { [weak self] chunkURL in
                self?.transcribeChunk(url: chunkURL)
            }
        } else {
            recorder.onChunkReady = nil
        }

        recorder.onSessionCap = { [weak self] in
            self?.handleRecordingStop()
        }
        recorder.onSilenceTimeout = {
            // Lock mode ends only via double-tap fn or session cap — never silence.
        }

        // Hold and lock: no silence auto-stop. Session cap (default 10 min) is the only auto-end.
        let silenceTimeout: Double? = nil

        do {
            let outputURL: URL
            if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
                outputURL = RecordingStore.tempRecordingURL()
            } else {
                outputURL = RecordingStore.newRecordingURL()
            }
            try recorder.startRecording(
                to: outputURL,
                streamingChunkSeconds: streamingOn ? (config.streamingChunkSeconds ?? 2.0) : nil,
                sessionCapSeconds: Double(
                    effectiveMaximumDurationMilliseconds(
                        for: captureProfileID
                    )
                ) / 1_000,
                silenceTimeoutSeconds: silenceTimeout
            )
        } catch {
            let msg = FailurePresenter.message(for: error)
            print("Error: \(msg)")
            isPressed = false
            statusBar.state = .error(msg)
            LocalVoiceStore.shared.setError(msg)
            pillOverlay.show(state: .error)
            pillOverlay.hide()
            dashboardCaptureMode = false
        }
    }

    private func transcribeChunk(url: URL) {
        streamingQueue.async { [weak self] in
            guard let self = self else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            let partial: String?
            if let engine = self.sttRouter.chunkEngine() {
                partial = try? engine.transcribe(audioURL: url)
            } else {
                let tiny = Transcriber(modelSize: "tiny.en", language: self.config.language)
                partial = try? tiny.transcribe(audioURL: url)
            }
            guard let text = partial, !text.isEmpty else { return }
            DispatchQueue.main.async {
                if !self.streamingPartial.isEmpty { self.streamingPartial += " " }
                self.streamingPartial += text
                self.pillOverlay.updatePartial(self.streamingPartial)
            }
        }
    }

    private func handleRecordingStop() {
        guard isPressed else { return }
        isPressed = false
        isLockMode = false
        for m in hotkeyManagers { m.resetLockState() }
        LatencyInstrumentation.shared.end("record")

        guard let audioURL = recorder.stopRecording() else {
            statusBar.state = .idle
            pillOverlay.hide()
            return
        }

        statusBar.state = .transcribing
        LocalVoiceStore.shared.setState(.transcribing, detail: "Finishing locally with \(sttRouter.activeEngineName())")
        if config.showCursorHUD?.value ?? true {
            pillOverlay.show(state: .transcribing, partialText: streamingPartial.isEmpty ? nil : streamingPartial)
        }

        let requestID = captureRequestID
        let profileID = captureProfileID
        let applicationName = captureApplicationName
        let bundleIdentifier = captureBundleIdentifier
        let modeName = captureModeName
        let maximumDurationMilliseconds =
            effectiveMaximumDurationMilliseconds(for: profileID)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let maxRecordings = Config.effectiveMaxRecordings(self.config.maxRecordings)
            let contractAudio = try? LocalVoiceContract.audioDescriptor(
                for: audioURL
            )
            defer {
                if maxRecordings == 0 {
                    try? FileManager.default.removeItem(at: audioURL)
                }
            }
            do {
                LatencyInstrumentation.shared.mark("stt")
                let raw = try self.sttRouter.transcribe(audioURL: audioURL)
                LatencyInstrumentation.shared.end("stt")

                var text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(raw) : raw

                LatencyInstrumentation.shared.mark("llm")
                let vocab = VocabularyLearner.shared.merged(with: self.config.customVocabulary ?? [])
                if self.ollamaCleanup.enabled, OllamaCleanup.isReachable() {
                    DispatchQueue.main.async {
                        LocalVoiceStore.shared.setState(.refining, detail: "Applying your local writing mode")
                    }
                    let profile = AppPromptProfiles.profile(for: self.captureBundleIdentifier)
                    text = try self.ollamaCleanup.polish(
                        raw: text,
                        systemPrompt: profile.systemPrompt,
                        vocabulary: vocab
                    )
                    VocabularyLearner.shared.learnFromDiff(raw: raw, polished: text)
                }
                LatencyInstrumentation.shared.end("llm")

                TranscriptStore.shared.store(raw: raw, polished: text)
                let inferenceMs =
                    LatencyInstrumentation.shared.lastSession["stt"] ?? 0
                let cleanupMs =
                    LatencyInstrumentation.shared.lastSession["llm"] ?? 0
                let engineName = self.sttRouter.activeEngineName()
                let engineModel = self.sttRouter.activeEngineModelName()
                let engineRoute = self.sttRouter.activeExecutionRoute()
                let enginePersistent =
                    self.sttRouter.activeEngineIsPersistent()

                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }

                DispatchQueue.main.async {
                    LatencyInstrumentation.shared.mark("inject")
                    if !text.isEmpty {
                        self.lastTranscription = text
                        if self.dashboardCaptureMode {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } else {
                            self.inserter.insert(text: text)
                            VoiceCommandExecutor.shared.flush()
                        }
                    } else {
                        let msg = "Empty transcript — speak louder or check mic"
                        self.statusBar.state = .error(msg)
                        self.pillOverlay.show(state: .error, partialText: msg)
                    }
                    LatencyInstrumentation.shared.end("inject")
                    fputs("Latency: \(LatencyInstrumentation.shared.summary())\n", stderr)
                    LatencyPanelController.shared.refresh()

                    if !text.isEmpty {
                        VocabularyLearner.shared.observeCorrection(inserted: raw, polished: text)
                        let recordMs = LatencyInstrumentation.shared.lastSession["record"] ?? 0
                        let injectionMs =
                            LatencyInstrumentation.shared.lastSession["inject"] ?? 0
                        let finishMs = inferenceMs + cleanupMs + injectionMs
                        var contractPair: VoiceContractPair?
                        if maxRecordings == 0, let contractAudio {
                            do {
                                contractPair = try LocalVoiceContract.makePair(
                                    requestId: requestID,
                                    profileId: profileID,
                                    audio: contractAudio,
                                    requestedLanguage: self.config.language,
                                    detectedLanguage: nil,
                                    enginePreference: self.config.sttEngine ?? .auto,
                                    configuredModel: self.config.modelSize,
                                    keepWarm: self.config.keepModelWarm?.value ?? true,
                                    promptVocabulary: vocab,
                                    maximumDurationMilliseconds:
                                        maximumDurationMilliseconds,
                                    rawTranscript: raw,
                                    normalizedTranscript: text,
                                    engineName: engineName,
                                    engineModel: engineModel,
                                    engineRoute: engineRoute,
                                    enginePersistent: enginePersistent,
                                    inferenceMilliseconds: inferenceMs,
                                    finishMilliseconds: cleanupMs + injectionMs,
                                    transcriptRetention: .localHistory
                                )
                            } catch {
                                fputs(
                                    "Voice contract receipt unavailable: \(error.localizedDescription)\n",
                                    stderr
                                )
                            }
                        }
                        if self.config.saveTranscriptHistory?.value ?? true {
                            LocalVoiceStore.shared.append(
                                LocalVoiceRecord(
                                    id: requestID,
                                    rawText: raw,
                                    polishedText: text,
                                    applicationName: applicationName,
                                    bundleIdentifier: bundleIdentifier,
                                    modeName: modeName,
                                    engineName: engineName,
                                    language: self.config.language,
                                    recordingMilliseconds: recordMs,
                                    finishMilliseconds: finishMs,
                                    contractPair: contractPair
                                )
                            )
                        }
                    }

                    self.statusBar.sttEngineName = self.sttRouter.activeEngineName()
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                    self.pillOverlay.hide()
                    self.dashboardCaptureMode = false
                    LocalVoiceStore.shared.updateRuntime {
                        $0.state = .ready
                        $0.engineName = self.sttRouter.activeEngineName()
                        $0.modelName = self.config.modelSize
                        $0.statusDetail = "Hold \(self.config.hotkeySummary()) to dictate anywhere"
                    }
                }
            } catch {
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                let msg = FailurePresenter.message(for: error)
                DispatchQueue.main.async {
                    print("Error: \(msg)")
                    self.statusBar.state = .error(msg)
                    self.statusBar.buildMenu()
                    LocalVoiceStore.shared.setError(msg)
                    self.pillOverlay.show(state: .error, partialText: msg)
                    self.dashboardCaptureMode = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if case .error = self.statusBar.state {
                            self.statusBar.state = .idle
                            self.statusBar.buildMenu()
                        }
                        self.pillOverlay.hide()
                    }
                }
            }
        }
    }

    private func effectiveMaximumDurationMilliseconds(
        for profile: VoiceContractProfileID
    ) -> Int {
        let profileLimit = profile.maximumDurationMilliseconds
        guard let configuredSeconds = config.sessionCapSeconds,
              configuredSeconds > 0 else {
            return profileLimit
        }
        let configured = Int((configuredSeconds * 1_000).rounded())
        return min(profileLimit, max(1_000, configured))
    }

    public func reprocess(audioURL: URL) {
        guard case .idle = statusBar.state else { return }

        statusBar.state = .transcribing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let raw = try self.sttRouter.transcribe(audioURL: audioURL)
                let text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(raw) : raw
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        self.lastTranscription = text
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.statusBar.state = .copiedToClipboard
                        self.statusBar.buildMenu()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.statusBar.state = .idle
                            self.statusBar.buildMenu()
                        }
                    } else {
                        self.statusBar.state = .idle
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("Reprocess error: \(error.localizedDescription)")
                    self.statusBar.state = .idle
                }
            }
        }
    }
}
