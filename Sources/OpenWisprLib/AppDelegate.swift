import AppKit

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
    private let streamingQueue = DispatchQueue(label: "local-flow.streaming", qos: .userInitiated)

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
            self.statusBar.buildMenu()
        }

        if Transcriber.findWhisperBinary() == nil {
            print("Error: whisper-cpp not found. Install it with: brew install whisper-cpp")
            return
        }

        if Permissions.didUpgrade() {
            print("Accessibility: upgrade detected, resetting permissions...")
            Permissions.resetAccessibility()
            Thread.sleep(forTimeInterval: 1)
        }

        if !AXIsProcessTrusted() {
            DispatchQueue.main.async {
                self.statusBar.state = .waitingForPermission
                self.statusBar.buildMenu()
            }
        }

        Permissions.ensureMicrophone()

        if !AXIsProcessTrusted() {
            print("Accessibility: not granted")
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
            print("Waiting for Accessibility permission...")
            while !AXIsProcessTrusted() {
                Thread.sleep(forTimeInterval: 0.5)
            }
            print("Accessibility: granted")
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
                let msg = "Model file is corrupted. Re-download with: open-wispr download-model \(config.modelSize)"
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

        Permissions.ensureInputMonitoring()

        let privacy = PrivacySelfTest.run(router: sttRouter)
        if config.showPrivacyBadge?.value ?? true {
            print("Privacy self-test: \(privacy.message)")
        }

        DispatchQueue.main.async { [weak self] in
            self?.startListening()
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
            }
        }
    }

    func toggleRawPolished() {
        let text = TranscriptStore.shared.toggle()
        inserter.insert(text: text)
    }

    private func startListening() {
        for m in hotkeyManagers { m.stop() }
        hotkeyManagers = []
        let globalToggle = config.toggleMode?.value ?? false
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
            manager.start(
                onKeyDown: { [weak self] in
                    self?.handleKeyDown()
                },
                onKeyUp: { [weak self] in
                    self?.handleKeyUp()
                }
            )
            hotkeyManagers.append(manager)
        }

        isReady = true
        statusBar.state = .idle
        statusBar.sttEngineName = sttRouter.activeEngineName()
        statusBar.buildMenu()

        let hotkeyDesc = config.hotkeySummary()
        print("Local Flow v\(OpenWispr.version)")
        if config.showPrivacyBadge?.value ?? true {
            print("Privacy: 100% on-device — zero network egress by default")
        }
        print("Hotkey: \(hotkeyDesc)")
        print("STT: \(sttRouter.activeEngineName())")
        print("Model: \(config.modelSize)")
        print("Ready.")
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

        for m in hotkeyManagers { m.stop() }
        hotkeyManagers = []
        let globalToggle = config.toggleMode?.value ?? false
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
            manager.start(
                onKeyDown: { [weak self] in self?.handleKeyDown() },
                onKeyUp: { [weak self] in self?.handleKeyUp() }
            )
            hotkeyManagers.append(manager)
        }

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
        streamingPartial = ""
        LatencyInstrumentation.shared.reset()
        LatencyInstrumentation.shared.mark("record")

        statusBar.state = .recording
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
        recorder.onSilenceTimeout = { [weak self] in
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
                sessionCapSeconds: config.sessionCapSeconds,
                silenceTimeoutSeconds: silenceTimeout
            )
        } catch {
            let msg = FailurePresenter.message(for: error)
            print("Error: \(msg)")
            isPressed = false
            statusBar.state = .error(msg)
            pillOverlay.show(state: .error)
            pillOverlay.hide()
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
        if config.showCursorHUD?.value ?? true {
            pillOverlay.show(state: .transcribing, partialText: streamingPartial.isEmpty ? nil : streamingPartial)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let maxRecordings = Config.effectiveMaxRecordings(self.config.maxRecordings)
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
                    let profile = AppPromptProfiles.profile(for: AppPromptProfiles.frontmostBundleID())
                    text = try self.ollamaCleanup.polish(
                        raw: text,
                        systemPrompt: profile.systemPrompt,
                        vocabulary: vocab
                    )
                    VocabularyLearner.shared.learnFromDiff(raw: raw, polished: text)
                }
                LatencyInstrumentation.shared.end("llm")

                TranscriptStore.shared.store(raw: raw, polished: text)

                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }

                DispatchQueue.main.async {
                    LatencyInstrumentation.shared.mark("inject")
                    if !text.isEmpty {
                        self.lastTranscription = text
                        self.inserter.insert(text: text)
                        VoiceCommandExecutor.shared.flush()
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
                    }

                    self.statusBar.sttEngineName = self.sttRouter.activeEngineName()
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                    self.pillOverlay.hide()
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
                    self.pillOverlay.show(state: .error, partialText: msg)
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
