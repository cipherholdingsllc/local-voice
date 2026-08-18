import AppKit
import ApplicationServices
import AVFoundation

private enum RecordingStopReason {
    case user
    case sessionLimit
}

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManagers: [CGEventHotkeyManager] = []
    private var shortcutCaptureActive = false
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
    private let streamingSessionGate = StreamingSessionGate()
    private let liveComposer = LiveFieldComposer()
    private var captureVisibleSpellings: [String] = []
    private var dashboardCaptureMode = false
    private var captureApplicationName = "Unknown app"
    private var captureBundleIdentifier: String?
    private var captureModeName = "Default"
    private var captureRequestID = UUID()
    private var captureProfileID = VoiceContractProfileID.generalDefault
    private let permissionCoordinator = PermissionCoordinator()
    private var permissionRepairTimer: Timer?
    private var permissionRepairDeadline: Date?
    private var permissionRepairOpenedCapability:
        LocalVoicePermissionCapability?
    private var didOfferAccessibilityRepair = false
    private var wakeObserver: NSObjectProtocol?
    private var frontmostObserver: NSObjectProtocol?
    private var lastFrontmostBundleID: String?
    private var vocabularyObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard LocalVoiceSingleInstanceGuard.claimCurrentProcess() else {
            NSApp.terminate(nil)
            return
        }
        statusBar = StatusBarController()
        recorder = AudioRecorder()
        startWakeMonitoring()
        startFrontmostMonitoring()
        showDashboard()

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
        vocabularyObserver = NotificationCenter.default.addObserver(
            forName: VocabularyLearner.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshVocabularyPrompt()
        }
        ollamaCleanup = OllamaCleanup(
            model: config.ollamaModel ?? "llama3.2:latest",
            enabled: config.ollamaEnabled?.value ?? false
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

        Permissions.ensureMicrophone { [weak self] _ in
            self?.refreshPermissionState(force: true)
        }

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
            }
            self.refreshPermissionState(force: true)
        }

        DispatchQueue.main.async { [weak self] in
            self?.startListening()
            self?.startPermissionMonitoring()
            OnboardingWizard.showIfNeeded()
        }
    }

    private func rebuildSTTRouter() {
        let prompt = VocabularyLearner.shared.promptString(
            configTerms: config.customVocabulary ?? []
        )
        sttRouter = STTRouter(
            language: config.language,
            modelSize: config.modelSize,
            preferredEngine: config.sttEngine ?? .auto,
            spokenPunctuation: config.spokenPunctuation?.value ?? false,
            initialPrompt: prompt.isEmpty ? nil : prompt,
            interactiveAccuracyFirst: config.dictationAccuracyFirstEnabled
        )
    }

    private func refreshVocabularyPrompt() {
        let prompt = VocabularyLearner.shared.promptString(
            configTerms: config.customVocabulary ?? []
        )
        sttRouter?.updateInitialPrompt(prompt.isEmpty ? nil : prompt)
    }

    func runPrivacySelfTest() {
        guard isReady else { return }
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
            }
            if result.passed {
                self.refreshPermissionState(force: true)
            } else {
                LocalVoiceStore.shared.setState(
                    .error,
                    detail: result.message
                )
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
                },
                shortcutCaptureChanged: { [weak self] active in
                    self?.setShortcutCaptureActive(active)
                },
                setShortcut: { [weak self] hotkey in
                    self?.setShortcut(hotkey)
                        ?? "Local Voice is not available to update the shortcut."
                }
            )
        )
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        guard isReady else { return }
        refreshPermissionState()
    }

    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showDashboard()
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        permissionRepairTimer?.invalidate()
        permissionRepairTimer = nil
        permissionRepairDeadline = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
            self.frontmostObserver = nil
        }
        for manager in hotkeyManagers { manager.stop() }
        hotkeyManagers = []
        sttRouter?.shutdown(preserveParakeet: false)
    }

    private func startWakeMonitoring() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recoverAfterSystemWake()
        }
    }

    private func startFrontmostMonitoring() {
        lastFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.surviveFrontmostChange(note)
        }
    }

    /// Cursor installs a session tap when it becomes frontmost and macOS
    /// disables ours. Re-enable in place — do not call startListening().
    private func surviveFrontmostChange(_ note: Notification) {
        guard isReady, !shortcutCaptureActive else { return }
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let current = app?.bundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let previous = lastFrontmostBundleID
        lastFrontmostBundleID = current
        guard HotkeyTapSurvival.shouldRearmOnFrontmostChange(
            previousBundleID: previous,
            currentBundleID: current
        ) else { return }
        for manager in hotkeyManagers {
            manager.surviveFrontmostChange(bundleID: current)
        }
        if HotkeyTapSurvival.isCompetingEditor(current) {
            fputs(
                "Local Voice: re-enabled fn tap after switch to \(current ?? "cursor")\n",
                stderr
            )
        }
    }

    private func recoverAfterSystemWake() {
        guard isReady else { return }

        // A missed fn key-up leaves isPressed true, which used to skip this
        // entire recovery and swallow every later hold. Cancel the stale
        // session, then recreate the event tap. reload() tears down audio, so
        // it must not run against a live take.
        if isPressed {
            handleRecordingCancel()
        }
        isLockMode = false

        recorder.reload()
        if !shortcutCaptureActive {
            startListening()
        }

        guard config.keepModelWarm?.value ?? true,
              let router = sttRouter else {
            print("Wake recovery: hotkey and audio re-armed")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            router.warmup()
            print("Wake recovery: hotkey and audio re-armed; local model warm")
        }
    }

    private func toggleDashboardCapture() {
        guard isReady else { return }
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
        insertTranscribedText(text)
    }

    @discardableResult
    private func insertTranscribedText(_ text: String) -> TextInsertOutcome {
        let outcome = inserter.insert(text: text)
        refreshPermissionState(force: true)
        if let message = outcome.operatorMessage {
            statusBar.state = .error(message)
            if config.showCursorHUD?.value ?? true {
                pillOverlay.show(state: .error, partialText: message)
            }
            if outcome == .copiedNeedsAccessibility, !didOfferAccessibilityRepair {
                didOfferAccessibilityRepair = true
                Permissions.openAccessibilitySettings()
            }
        }
        return outcome
    }

    private func persistPermissionProbe() {
        let snapshot = permissionCoordinator.latestSnapshot ?? Permissions.snapshot()
        try? LocalVoicePermissionProbe.make(
            snapshot: snapshot,
            hotkeyMonitorReady: permissionCoordinator.hotkeyMonitorReady,
            tapAttempted: !config.hotkeys.isEmpty,
            tapStarted: !hotkeyManagers.isEmpty
        ).write()
    }

    private func startListening() {
        for m in hotkeyManagers { m.stop() }
        hotkeyManagers = []
        permissionCoordinator.updateHotkeyMonitorReady(false)

        let globalToggle = config.toggleMode?.value ?? false
        InputMonitoringAccess.registerWithTCC()
        for hk in config.hotkeys {
                let mode = hk.resolvedActivationMode(globalToggle: globalToggle)
                let manager = CGEventHotkeyManager(
                    keyCode: hk.keyCode,
                    modifiers: hk.modifierFlags,
                    activationMode: mode
                )
                manager.onLockChanged = { [weak self] locked in
                    guard let self else { return }
                    self.isLockMode = locked
                    if locked {
                        // Promote the already-running take to a matching
                        // long-form recorder + contract policy. This prevents
                        // Terminal/Codex's two-minute hold cap from silently
                        // ending a deliberately locked session.
                        self.captureProfileID = RecordingSessionPolicy.lockedProfile
                        self.recorder.updateSessionCap(
                            seconds: RecordingSessionPolicy.capSeconds(
                                for: self.captureProfileID,
                                configuredCapSeconds: self.config.sessionCapSeconds
                            )
                        )
                    }
                    DispatchQueue.main.async {
                        if locked {
                            self.pillOverlay.show(state: .locked)
                        }
                    }
                }
                let started = manager.start(
                    onKeyDown: { [weak self] in
                        self?.handleKeyDown()
                    },
                    onKeyUp: { [weak self] in
                        self?.handleKeyUp()
                    },
                    onKeyCancel: { [weak self] in
                        self?.handleRecordingCancel()
                    }
                )
                if started {
                    hotkeyManagers.append(manager)
                } else {
                    fputs(
                        "Local Voice: failed to start \(config.hotkeySummary()) event tap — check Input Monitoring for ~/Applications/Local Voice.app\n",
                        stderr
                    )
                }
        }
        permissionCoordinator.updateHotkeyMonitorReady(
            !config.hotkeys.isEmpty
            && hotkeyManagers.count == config.hotkeys.count
        )

        let probeSnapshot = permissionCoordinator.refresh().current
        try? LocalVoicePermissionProbe.make(
            snapshot: probeSnapshot,
            hotkeyMonitorReady: permissionCoordinator.hotkeyMonitorReady,
            tapAttempted: !config.hotkeys.isEmpty,
            tapStarted: !hotkeyManagers.isEmpty
        ).write()

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
        applyPermissionSnapshot(probeSnapshot)

        let hotkeyDesc = config.hotkeySummary()
        print("Local Voice v\(OpenWispr.version)")
        if config.showPrivacyBadge?.value ?? true {
            print("Privacy: local speech process or loopback route; no hosted STT configured")
        }
        print("Hotkey: \(hotkeyDesc)")
        print("STT: \(sttRouter.activeEngineName())")
        print("Model: \(config.modelSize)")
        if permissionCoordinator.hotkeyMonitorReady {
            print("Hotkey monitor: active")
        } else {
            print("Hotkey monitor: unavailable")
        }
        print(permissionCoordinator.runtimeReady ? "Ready." : "Needs permission.")
    }

    private func startPermissionMonitoring() {
        refreshPermissionState()
    }

    private func refreshPermissionState(force: Bool = false) {
        let refresh = permissionCoordinator.refresh()
        let snapshot = refresh.current
        persistPermissionProbe()
        guard isReady else {
            LocalVoiceStore.shared.updateRuntime {
                $0.accessibilityReady = snapshot.accessibility
                $0.microphoneReady = snapshot.microphone
                $0.inputMonitoringReady = snapshot.inputMonitoring
                $0.hotkeyReady = false
            }
            return
        }
        if refresh.inputMonitoringChanged {
            startListening()
            return
        }
        if refresh.changed || force {
            applyPermissionSnapshot(snapshot)
        }
    }

    private func applyPermissionSnapshot(
        _ snapshot: LocalVoicePermissionSnapshot
    ) {
        LocalVoiceStore.shared.updateRuntime {
            $0.applyPermissionReadiness(
                snapshot,
                hotkeyMonitorReady:
                    self.permissionCoordinator.hotkeyMonitorReady,
                hotkeySummary: self.config.hotkeySummary()
            )
        }

        guard !isPressed else { return }
        if permissionCoordinator.runtimeReady {
            statusBar.state = .idle
        } else {
            statusBar.permissionDetail =
                snapshot.blockingSummary
                ?? "The \(config.hotkeySummary()) shortcut monitor could not start"
            statusBar.state = .waitingForPermission
        }
        statusBar.buildMenu()
    }

    func repairPermissions() {
        let snapshot = permissionCoordinator.refresh().current
        let plan = permissionCoordinator.repairPlan(for: snapshot)

        guard plan.primaryAction != nil else {
            permissionRepairOpenedCapability = nil
            LocalVoiceStore.shared.updateRuntime {
                $0.permissionRepairDetail = nil
            }
            if isReady {
                startListening()
                refreshPermissionState(force: true)
            } else {
                LocalVoiceStore.shared.setState(
                    .preparing,
                    detail: "Permissions are available. Local Voice is finishing speech-engine setup."
                )
            }
            showDashboard()
            return
        }

        permissionRepairOpenedCapability = nil
        showDashboard()
        startBoundedPermissionRepairMonitoring()
        advancePermissionRepair(plan)
    }

    private func startBoundedPermissionRepairMonitoring() {
        permissionRepairTimer?.invalidate()
        permissionRepairDeadline = Date().addingTimeInterval(180)
        permissionRepairTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] timer in
            guard let self,
                  let deadline = self.permissionRepairDeadline,
                  Date() < deadline else {
                timer.invalidate()
                self?.permissionRepairTimer = nil
                self?.permissionRepairDeadline = nil
                return
            }

            self.refreshPermissionState()
            let plan = self.permissionCoordinator.repairPlan()
            if self.permissionCoordinator.runtimeReady {
                timer.invalidate()
                self.permissionRepairTimer = nil
                self.permissionRepairDeadline = nil
                self.permissionRepairOpenedCapability = nil
                LocalVoiceStore.shared.updateRuntime {
                    $0.permissionRepairDetail = nil
                }
                NSApp.activate(ignoringOtherApps: true)
                self.showDashboard()
                return
            }
            self.advancePermissionRepair(plan)
        }
        if let permissionRepairTimer {
            RunLoop.main.add(permissionRepairTimer, forMode: .common)
        }
    }

    private func advancePermissionRepair(
        _ plan: LocalVoicePermissionRepairPlan
    ) {
        let detail = [plan.instruction, plan.signingWarning]
            .compactMap { $0 }
            .joined(separator: " ")
        LocalVoiceStore.shared.updateRuntime {
            $0.state = .error
            $0.permissionRepairDetail = detail
        }

        guard let capability = plan.primaryCapability,
              capability != permissionRepairOpenedCapability,
              let action = plan.primaryAction else {
            return
        }
        permissionRepairOpenedCapability = capability

        switch action {
        case .requestMicrophone:
            Permissions.ensureMicrophone { [weak self] granted in
                self?.refreshPermissionState(force: true)
                if !granted {
                    Permissions.openSettings(for: .microphone)
                }
            }
        case .openSettings(let capability):
            Permissions.openSettings(for: capability)
        }
    }

    public func reloadConfig() {
        guard isReady else { return }
        let newConfig = Config.load()
        applyConfigChange(newConfig)
    }

    private func setShortcutCaptureActive(_ active: Bool) {
        guard active != shortcutCaptureActive else { return }
        shortcutCaptureActive = active
        if active {
            for manager in hotkeyManagers { manager.stop() }
            hotkeyManagers = []
        } else if isReady, hotkeyManagers.isEmpty {
            startListening()
        }
    }

    private func setShortcut(_ hotkey: HotkeyConfig) -> String? {
        guard var newConfig = config else {
            setShortcutCaptureActive(false)
            return "Local Voice is still starting. Try changing the shortcut again in a moment."
        }
        newConfig.hotkey = hotkey
        do {
            try newConfig.save()
            shortcutCaptureActive = false
            applyConfigChange(newConfig)
            return nil
        } catch {
            setShortcutCaptureActive(false)
            return "The shortcut could not be saved: \(error.localizedDescription)"
        }
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
            enabled: config.ollamaEnabled?.value ?? false
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
        // If this callback fires, an event tap is already delivering key events.
        // Do not also require hotkeyMonitorReady — that flag is cleared during
        // startListening() restarts and would silently swallow live Fn presses.
        guard isReady, !hotkeyManagers.isEmpty else { return }

        if isPressed, !recorder.isRecording {
            fputs(
                "Local Voice: clearing stale fn hold; recorder was not running\n",
                stderr
            )
            isPressed = false
            isLockMode = false
        }

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
        streamingSessionGate.begin(captureRequestID)
        captureProfileID = VoiceContractProfileID.localVoiceProfile(
            bundleIdentifier: captureBundleIdentifier,
            modeName: captureModeName
        )
        streamingPartial = ""
        liveComposer.reset()
        captureVisibleSpellings = []
        if !dashboardCaptureMode {
            captureVisibleSpellings = NearbyContextSampler.sampleVisibleSpellings()
            liveComposer.begin()
        }
        LatencyInstrumentation.shared.reset()
        LatencyInstrumentation.shared.mark("record")

        recorder.onLevel = { [weak self] level in
            self?.pillOverlay.updateLevel(level)
        }

        let streamingOn = config.streamingEnabled?.value ?? true
        if streamingOn {
            let streamingRequestID = captureRequestID
            recorder.onChunkReady = { [weak self] chunkURL in
                self?.transcribeChunk(
                    url: chunkURL,
                    requestID: streamingRequestID
                )
            }
        } else {
            recorder.onChunkReady = nil
        }

        recorder.onSessionCap = { [weak self] in
            self?.handleRecordingStop(reason: .sessionLimit)
        }
        recorder.onSilenceTimeout = {
            // Lock mode ends only via double-tap fn or session cap — never silence.
        }

        // Silence never auto-stops a take. Hold recordings retain the profile
        // safety cap; double-tap lock removes it until the user unlocks.
        let silenceTimeout: Double? = nil

        do {
            let outputURL: URL
            if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
                outputURL = RecordingStore.tempRecordingURL()
            } else {
                outputURL = RecordingStore.newRecordingURL()
            }
            LatencyInstrumentation.shared.mark("capture-start")
            try recorder.startRecording(
                to: outputURL,
                streamingChunkSeconds: streamingOn ? (config.streamingChunkSeconds ?? 2.0) : nil,
                sessionCapSeconds: RecordingSessionPolicy.capSeconds(
                    for: captureProfileID,
                    configuredCapSeconds: config.sessionCapSeconds
                ),
                silenceTimeoutSeconds: silenceTimeout
            )
            LatencyInstrumentation.shared.end("capture-start")
            statusBar.state = .recording
            LocalVoiceStore.shared.setState(.listening, detail: "Speak naturally. Click stop when finished.")
            if config.showCursorHUD?.value ?? true {
                pillOverlay.show(state: .listening)
            }
        } catch {
            streamingSessionGate.end(captureRequestID)
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

    /// Discards the speculative recording made by the first short fn tap.
    /// The hotkey manager deliberately keeps its gesture state so a second tap
    /// can engage lock mode without sacrificing instant audio onset.
    private func handleRecordingCancel() {
        guard isPressed else { return }
        isPressed = false
        streamingSessionGate.end(captureRequestID)
        LatencyInstrumentation.shared.end("record")

        if let audioURL = recorder.stopRecording() {
            try? FileManager.default.removeItem(at: audioURL)
        }

        streamingPartial = ""
        liveComposer.cancel()
        captureVisibleSpellings = []
        statusBar.state = .idle
        pillOverlay.hide()
        dashboardCaptureMode = false
        refreshPermissionState(force: true)
    }

    private func transcribeChunk(url: URL, requestID: UUID) {
        streamingQueue.async { [weak self] in
            guard let self = self else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            guard self.streamingSessionGate.isActive(requestID) else {
                return
            }
            let partial: String?
            if let engine = self.sttRouter.chunkEngine() {
                partial = try? engine.transcribe(audioURL: url)
            } else {
                let tiny = Transcriber(modelSize: "tiny.en", language: self.config.language)
                partial = try? tiny.transcribe(audioURL: url)
            }
            guard
                self.streamingSessionGate.isActive(requestID),
                let text = partial,
                !text.isEmpty
            else { return }
            DispatchQueue.main.async {
                guard self.streamingSessionGate.isActive(requestID) else {
                    return
                }
                self.streamingPartial = StreamingTranscriptAssembler.merge(
                    existing: self.streamingPartial,
                    incoming: text
                )
                let cleaned = VocabularyLearner.shared.postProcess(
                    self.streamingPartial,
                    configTerms: self.config.customVocabulary ?? [],
                    visibleSpellings: self.captureVisibleSpellings,
                    pokerVocabularyEnabled: self.captureProfileID == .pokerExploit
                )
                self.streamingPartial = cleaned
                self.pillOverlay.updatePartial(self.streamingPartial)
                if !self.dashboardCaptureMode {
                    self.liveComposer.updatePartial(self.streamingPartial)
                }
            }
        }
    }

    private func handleRecordingStop(reason: RecordingStopReason = .user) {
        guard isPressed else { return }
        isPressed = false
        isLockMode = false
        streamingSessionGate.end(captureRequestID)
        for m in hotkeyManagers { m.resetLockState() }
        LatencyInstrumentation.shared.end("record")

        guard let audioURL = recorder.stopRecording() else {
            statusBar.state = .idle
            pillOverlay.hide()
            return
        }

        let captureMetrics = recorder.captureMetricsSnapshot()
        guard captureMetrics.shouldAttemptTranscription else {
            try? FileManager.default.removeItem(at: audioURL)
            streamingPartial = ""
            statusBar.state = .idle
            statusBar.buildMenu()
            let detail = "No audio captured — check microphone input in System Settings"
            LocalVoiceStore.shared.setState(.ready, detail: detail)
            if config.showCursorHUD?.value ?? true {
                pillOverlay.show(state: .error, partialText: detail)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.pillOverlay.hide()
                }
            }
            pillOverlay.hide()
            dashboardCaptureMode = false
            refreshPermissionState(force: true)
            return
        }

        statusBar.state = .transcribing
        let finishingDetail = reason == .sessionLimit
            ? "One-hour locked-session safety limit reached; finishing locally"
            : "Finishing locally with \(sttRouter.activeEngineName())"
        LocalVoiceStore.shared.setState(.transcribing, detail: finishingDetail)
        if config.showCursorHUD?.value ?? true {
            pillOverlay.show(state: .transcribing, partialText: streamingPartial.isEmpty ? nil : streamingPartial)
        }

        let requestID = captureRequestID
        let profileID = captureProfileID
        let applicationName = captureApplicationName
        let bundleIdentifier = captureBundleIdentifier
        let modeName = captureModeName
        let visibleSpellings = captureVisibleSpellings
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
                let recordingMs =
                    LatencyInstrumentation.shared.lastSession["record"] ?? 0
                let raw = try self.sttRouter.transcribeInteractive(
                    audioURL: audioURL,
                    recordingMilliseconds: recordingMs
                )
                LatencyInstrumentation.shared.end("stt")

                var text = TextPostProcessor.processStructural(raw)
                if self.config.spokenPunctuation?.value ?? false {
                    text = TextPostProcessor.process(text)
                }
                let taught = DictationTeacher.consume(text)
                text = VocabularyLearner.shared.postProcess(
                    taught.text,
                    configTerms: self.config.customVocabulary ?? [],
                    visibleSpellings: visibleSpellings,
                    pokerVocabularyEnabled: profileID == .pokerExploit
                )

                LatencyInstrumentation.shared.mark("llm")
                let vocab = VocabularyLearner.shared.merged(with: self.config.customVocabulary ?? [])
                let cleanupRoute = DictationCleanupPolicy.route(
                    enabled: self.ollamaCleanup.enabled,
                    characterCount: text.count,
                    recordingMilliseconds: recordingMs
                )
                if cleanupRoute == .synchronousOllama,
                   OllamaCleanup.isReachable() {
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
                } else if cleanupRoute == .fastLongForm {
                    fputs(
                        "Cleanup: fast long-form route (\(Int(recordingMs))ms, \(text.count) characters)\n",
                        stderr
                    )
                }
                LatencyInstrumentation.shared.end("llm")

                let teachOnly = taught.learned
                    && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                guard teachOnly || TranscriptAcceptanceGate.shouldAccept(
                    raw: raw,
                    polished: text,
                    recordingMilliseconds: recordingMs,
                    captureMetrics: captureMetrics
                ) else {
                    fputs(
                        "Rejected low-confidence transcript: raw='\(raw)' polished='\(text)' recordingMs=\(Int(recordingMs))\n",
                        stderr
                    )
                    DispatchQueue.main.async {
                        self.streamingPartial = ""
                        self.liveComposer.cancel()
                        self.captureVisibleSpellings = []
                        self.statusBar.state = .idle
                        self.statusBar.buildMenu()
                        self.pillOverlay.hide()
                        self.dashboardCaptureMode = false
                        LocalVoiceStore.shared.setState(
                            .ready,
                            detail: "Low-confidence transcript; nothing was inserted"
                        )
                        self.refreshPermissionState(force: true)
                    }
                    return
                }

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
                    if let message = taught.message {
                        LocalVoiceStore.shared.setState(.ready, detail: message)
                        if self.config.showCursorHUD?.value ?? true {
                            self.pillOverlay.show(state: .transcribing, partialText: message)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                self.pillOverlay.hide()
                            }
                        }
                    }
                    if !text.isEmpty {
                        self.lastTranscription = text
                        if self.dashboardCaptureMode {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } else if self.liveComposer.hasLiveInsertion {
                            if !self.liveComposer.commitFinal(text) {
                                self.insertTranscribedText(text)
                            }
                            VoiceCommandExecutor.shared.flush()
                        } else {
                            self.insertTranscribedText(text)
                            VoiceCommandExecutor.shared.flush()
                        }
                        self.captureVisibleSpellings = []
                    } else if taught.message != nil {
                        self.liveComposer.cancel()
                        self.captureVisibleSpellings = []
                        self.statusBar.state = .idle
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
                        $0.engineName = self.sttRouter.activeEngineName()
                        $0.modelName = self.config.modelSize
                    }
                    self.refreshPermissionState(force: true)
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
        RecordingSessionPolicy.maximumDurationMilliseconds(
            for: profile,
            configuredCapSeconds: config.sessionCapSeconds
        )
    }

    public func reprocess(audioURL: URL) {
        guard case .idle = statusBar.state else { return }

        statusBar.state = .transcribing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let raw = try self.sttRouter.transcribe(audioURL: audioURL)
                var text = TextPostProcessor.processStructural(raw)
                if self.config.spokenPunctuation?.value ?? false {
                    text = TextPostProcessor.process(text)
                }
                text = VocabularyLearner.shared.postProcess(
                    text,
                    configTerms: self.config.customVocabulary ?? [],
                    pokerVocabularyEnabled: self.captureProfileID == .pokerExploit
                )
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
