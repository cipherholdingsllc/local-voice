import AppKit
import AVFoundation
import Foundation
import OpenWisprLib

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)

let version = OpenWispr.version

func printUsage() {
    print("""
    Local Voice v\(version) — Private, system-wide dictation for macOS

    USAGE:
        local-voice start               Start Local Voice
        local-voice dashboard-preview   Open the fixture-backed GUI preview
        local-voice pill-preview <state> Preview Listening/Locked without recording
        local-voice glyph-sheet <out.png> [scale] [states...]
                                       Render the state glyph offscreen for review
        local-voice set-hotkey <key>    Set the push-to-talk hotkey
        local-voice get-hotkey          Show current hotkey
        local-voice set-model <size>    Set the Whisper model
        local-voice set-language <code> Set the language (e.g. en, fr, auto)
        local-voice download-model [size] Download a Whisper model
        local-voice benchmark [engine] [model] Run the local synthetic quality gate
        local-voice long-form-benchmark [engine] [model]
                                       Reproduce the long-dictation release gate
        local-voice real-speech-crucible <status|run|capture> [id]
                                       Operator real-speech baseline; no new ASR
        local-voice hotkey-diagnose      Test the real Fn event tap without recording
        local-voice contract-fixture    Emit a canonical request/response pair
        local-voice transcribe-file <path> [txt|md|json|srt|vtt]
                                       Transcribe and export a local audio/video file
        local-voice status              Show configuration and status
        local-voice --help              Show this help message

    HOTKEY EXAMPLES:
        local-voice set-hotkey globe             Globe/fn key (default)
        local-voice set-hotkey rightoption        Right Option key
        local-voice set-hotkey f5                 F5 key
        local-voice set-hotkey ctrl+space         Ctrl + Space

    AVAILABLE MODELS:
        \(Config.supportedModels.joined(separator: ", "))
    """)
}

func cmdStart() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    signal(SIGINT) { _ in
        print("\nStopping Local Voice...")
        exit(0)
    }

    app.run()
}

func cmdDashboardPreview() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    DashboardWindowController.shared.showPreview()
    app.run()
}

func cmdPillPreview(stateName: String?) {
    guard
        let stateName,
        let state = PillPreviewState(rawValue: stateName.lowercased())
    else {
        let names = PillPreviewState.allCases
            .map(\.rawValue)
            .joined(separator: ", ")
        fputs(
            "Usage: local-voice pill-preview <\(names)>\n",
            stderr
        )
        exit(2)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let preview = PillOverlayPreviewSession()
    guard preview.show(state: state) else {
        fputs("Could not present the \(state.rawValue) pill.\n", stderr)
        exit(1)
    }

    signal(SIGINT) { _ in
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
    app.run()
    withExtendedLifetime(preview) {}
}

func cmdGlyphSheet(path: String?, scale: String?, states: [String]) {
    guard let path, !path.isEmpty else {
        fputs(
            "Usage: local-voice glyph-sheet <out.png> [scale] [states...]\n",
            stderr
        )
        exit(2)
    }
    let expanded = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded).standardizedFileURL
    let resolved = scale.flatMap { Double($0) }.map { CGFloat($0) } ?? 3
    do {
        try GlyphSheet.render(
            to: url,
            options: GlyphSheet.Options(scale: resolved, states: states)
        )
        print("Wrote \(url.path)")
    } catch {
        fputs(
            "Glyph sheet failed: \(error.localizedDescription)\n",
            stderr
        )
        exit(1)
    }
}

func cmdSetHotkey(_ keyString: String) {
    guard let parsed = KeyCodes.parse(keyString) else {
        print("Error: Unknown key '\(keyString)'")
        print("Run 'local-voice --help' for examples")
        exit(1)
    }

    var config = Config.load()
    config.hotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)

    do {
        try config.save()
        let desc = KeyCodes.describe(keyCode: parsed.keyCode, modifiers: parsed.modifiers)
        print("Hotkey set to: \(desc)")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetModel(_ size: String) {
    guard Config.supportedModels.contains(size) else {
        print("Error: Unknown model '\(size)'")
        print("Available: \(Config.supportedModels.joined(separator: ", "))")
        exit(1)
    }

    var config = Config.load()
    config.modelSize = size

    do {
        try config.save()
        print("Model set to: \(size)")
        if !Transcriber.modelExists(modelSize: size) {
            print("Model will be downloaded on next start.")
        }
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdSetLanguage(_ lang: String) {
    let validCodes = Config.supportedLanguages.map { $0.code }
    guard validCodes.contains(lang) else {
        print("Error: Unknown language '\(lang)'")
        print("Available: auto, en, fr, de, es, zh, ja, ko, pt, it, nl, ru, ...")
        print("Run 'local-voice --help' for the supported model list.")
        exit(1)
    }

    var config = Config.load()
    config.language = lang

    do {
        try config.save()
        let name = Config.supportedLanguages.first(where: { $0.code == lang })?.name ?? lang
        print("Language set to: \(name) (\(lang))")
    } catch {
        print("Error saving config: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdGetHotkey() {
    let config = Config.load()
    let desc = config.hotkeySummary()
    print("Current hotkey: \(desc)")
}

func cmdDownloadModel(_ size: String) {
    do {
        try ModelDownloader.download(modelSize: size)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdStatus() {
    let config = Config.load()
    let hotkeyDesc = config.hotkeySummary()

    print("Local Voice v\(version)")
    print("Config:      \(Config.configFile.path)")
    print("Hotkey:      \(hotkeyDesc)")
    print("Model:       \(config.modelSize)")
    print("Model ready: \(Transcriber.modelExists(modelSize: config.modelSize) ? "yes" : "no")")
    print("whisper-cpp: \(Transcriber.findWhisperBinary() != nil ? "yes" : "no")")
    let langName = Config.supportedLanguages.first(where: { $0.code == config.language })?.name ?? config.language
    print("Language:    \(langName) (\(config.language))")
    let toggleMode = config.toggleMode?.value ?? false
    print("Toggle:      \(toggleMode ? "on (press to start/stop)" : "off (hold to talk)")")
    let permissions = Permissions.snapshot()
    print("Microphone:  \(permissions.microphone ? "granted" : "required")")
    print("Accessibility: \(permissions.accessibility ? "granted" : "required")")
    print("Input monitor: \(permissions.inputMonitoring ? "granted" : "required")")
    if Bundle.main.bundlePath.hasSuffix(".app") == false {
        print("Note:        CLI permission lines are Terminal's TCC, not Local Voice.app. Automic Vault Accessibility is a different app. Trust Command Center / ~/.config/local-voice/permission-snapshot.json.")
    }
    print("Launch login: \(LaunchAtLoginManager.statusSummary)")
}

func cmdBenchmark(engine: String?, model: String?) {
    let config = Config.load()
    let preference: STTEngineKind
    if let engine {
        guard let parsed = STTEngineKind(rawValue: engine) else {
            print("Error: benchmark engine must be auto, parakeet, or whisper")
            exit(1)
        }
        preference = parsed
    } else {
        preference = config.sttEngine ?? .auto
    }
    let selectedModel = model ?? config.modelSize
    guard Config.supportedModels.contains(selectedModel) else {
        print("Error: Unknown model '\(selectedModel)'")
        exit(1)
    }

    do {
        let report = try VoiceBenchmark.run(
            preferredEngine: preference,
            modelSize: selectedModel,
            language: "en"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        print(String(data: data, encoding: .utf8) ?? "{}")
        if !report.aggregate.passed { exit(2) }
    } catch {
        print("Benchmark failed: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdLongFormBenchmark(engine: String?, model: String?) {
    let config = Config.load()
    let preference: STTEngineKind
    if let engine {
        guard let parsed = STTEngineKind(rawValue: engine) else {
            print(
                "Error: benchmark engine must be auto, parakeet, or whisper"
            )
            exit(1)
        }
        preference = parsed
    } else {
        preference = config.sttEngine ?? .auto
    }
    let selectedModel = model ?? config.modelSize
    guard Config.supportedModels.contains(selectedModel) else {
        print("Error: Unknown model '\(selectedModel)'")
        exit(1)
    }

    do {
        let report = try LongFormLatencyBenchmark.run(
            preferredEngine: preference,
            modelSize: selectedModel,
            language: "en"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        print(String(data: data, encoding: .utf8) ?? "{}")
        if !report.passed { exit(2) }
    } catch {
        print(
            "Long-form benchmark failed: \(error.localizedDescription)"
        )
        exit(1)
    }
}

func cmdRealSpeechCrucible(action: String?, sampleID: String?) {
    let manifestURL = RealSpeechCrucible.defaultManifestURL()
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
        fputs(
            "Run this from the local-voice repo root so Benchmarks/real-speech-crucible/manifest.json is visible.\n",
            stderr
        )
        exit(2)
    }

    do {
        let manifest = try RealSpeechCrucible.loadManifest(from: manifestURL)
        let audioRoot = RealSpeechCrucible.defaultAudioRoot()
        switch action {
        case "status", nil:
            let status = RealSpeechCrucible.status(
                manifest: manifest,
                audioRoot: audioRoot
            )
            print("Real-Speech Crucible")
            print("Audio root: \(audioRoot.path)")
            print("Present:    \(status.present.count)/\(manifest.samples.count)")
            if !status.missing.isEmpty {
                print("Missing:    \(status.missing.joined(separator: ", "))")
                print("Capture:    local-voice real-speech-crucible capture <id>")
            }
            if status.present.isEmpty {
                print("Baseline:   not runnable — operator WAVs are the source of truth")
                exit(2)
            }
        case "run":
            let config = Config.load()
            let report = try RealSpeechCrucible.run(
                manifest: manifest,
                audioRoot: audioRoot,
                preferredEngine: config.sttEngine ?? .auto,
                modelSize: config.modelSize,
                language: config.language,
                configTerms: config.customVocabulary ?? [],
                ollamaEnabled: config.ollamaEnabled?.value ?? false
            )
            let traces = RealSpeechCrucible.defaultTraceRoot()
            try FileManager.default.createDirectory(
                at: traces,
                withIntermediateDirectories: true
            )
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "")
            let out = traces.appendingPathComponent(
                "baseline-\(stamp).json"
            )
            try RealSpeechCrucible.encode(report).write(to: out)
            if let text = String(data: try RealSpeechCrucible.encode(report), encoding: .utf8) {
                print(text)
            }
            fputs("Wrote \(out.path)\n", stderr)
            if report.aggregate.scoredSampleCount == 0 { exit(2) }
        case "capture":
            try cmdRealSpeechCapture(manifest: manifest, sampleID: sampleID)
        default:
            fputs(
                "Usage: local-voice real-speech-crucible <status|run|capture> [id]\n",
                stderr
            )
            exit(2)
        }
    } catch {
        fputs(
            "Real-speech crucible failed: \(error.localizedDescription)\n",
            stderr
        )
        exit(1)
    }
}

func cmdRealSpeechCapture(manifest: RealSpeechManifest, sampleID: String?) throws {
    let audioRoot = RealSpeechCrucible.defaultAudioRoot()
    try FileManager.default.createDirectory(
        at: audioRoot,
        withIntermediateDirectories: true
    )
    let samples: [RealSpeechSample]
    if let sampleID {
        guard let match = manifest.samples.first(where: { $0.id == sampleID }) else {
            fputs("Unknown sample \(sampleID)\n", stderr)
            exit(2)
        }
        samples = [match]
    } else {
        samples = manifest.samples.filter { sample in
            !FileManager.default.fileExists(
                atPath: audioRoot.appendingPathComponent(sample.audioFile).path
            )
        }
        if samples.isEmpty {
            print("All \(manifest.samples.count) operator WAVs are present.")
            return
        }
    }

    print("Quit Local Voice if the mic is busy. This records Terminal's input, not a new engine.")
    for sample in samples {
        let dest = audioRoot.appendingPathComponent(sample.audioFile)
        print("")
        print("[\(sample.id)] \(sample.condition)")
        print("SPEAK: \(sample.spokenScript)")
        print("Press Return to start, Return to stop.")
        _ = readLine()
        let recorder = try AVAudioRecorder(
            url: dest,
            settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )
        recorder.prepareToRecord()
        recorder.record()
        print("Recording…")
        _ = readLine()
        recorder.stop()
        print("Wrote \(dest.path)")
    }
}

func cmdContractFixture() {
    do {
        print(try LocalVoiceContract.samplePair().jsonString())
    } catch {
        print("Contract fixture failed: \(error.localizedDescription)")
        exit(1)
    }
}

func cmdHotkeyDiagnose() {
    _ = NSApplication.shared
    let report = HotkeyDiagnostic.runFnProbe()
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        print(String(data: data, encoding: .utf8) ?? "{}")
        if !report.passed { exit(2) }
    } catch {
        fputs(
            "Hotkey diagnostic failed: \(error.localizedDescription)\n",
            stderr
        )
        exit(1)
    }
}

func cmdTranscribeFile(path: String?, formatName: String?) {
    guard let path, !path.isEmpty else {
        fputs(
            "Usage: local-voice transcribe-file <path> [txt|md|json|srt|vtt]\n",
            stderr
        )
        exit(2)
    }
    let rawFormat = formatName?.lowercased() ?? "txt"
    guard let format = FileTranscriptFormat(rawValue: rawFormat) else {
        fputs(
            "Unsupported export '\(rawFormat)'. Use txt, md, json, srt, or vtt.\n",
            stderr
        )
        exit(2)
    }
    let expandedPath = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expandedPath)
        .standardizedFileURL
    do {
        let result = try LocalFileTranscriptionProcessor().process(
            url: url,
            progress: { _, _ in true }
        )
        let job = FileTranscriptionJob(
            filename: url.lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            status: .completed,
            progress: 1,
            durationMilliseconds: result.durationMilliseconds,
            transcript: result.transcript,
            engineSummary: result.engineSummary,
            routeSummary: result.routeSummary,
            segments: result.segments
        )
        let data = try FileTranscriptExporter.data(
            job: job,
            format: format
        )
        FileHandle.standardOutput.write(data)
    } catch {
        fputs(
            "File transcription failed: \(error.localizedDescription)\n",
            stderr
        )
        exit(1)
    }
}

let args = CommandLine.arguments
let rawCommand = args.count > 1 ? args[1] : nil
let command = LocalVoiceCommandResolver.resolve(
    rawCommand: rawCommand,
    executablePath: args[0]
)

switch command {
case "start":
    if AppBundleLaunch.relaunchThroughAppBundleIfNeeded() {
        exit(0)
    }
    cmdStart()
case "dashboard-preview":
    cmdDashboardPreview()
case "pill-preview":
    cmdPillPreview(stateName: args.count > 2 ? args[2] : nil)
case "glyph-sheet":
    cmdGlyphSheet(
        path: args.count > 2 ? args[2] : nil,
        scale: args.count > 3 ? args[3] : nil,
        states: args.count > 4 ? Array(args[4...]) : []
    )
case "set-hotkey":
    guard args.count > 2 else {
        print("Usage: local-voice set-hotkey <key>")
        exit(1)
    }
    cmdSetHotkey(args[2])
case "set-model":
    guard args.count > 2 else {
        print("Usage: local-voice set-model <size>")
        exit(1)
    }
    cmdSetModel(args[2])
case "set-language":
    guard args.count > 2 else {
        print("Usage: local-voice set-language <code>")
        print("Examples: en, fr, auto")
        exit(1)
    }
    cmdSetLanguage(args[2])
case "get-hotkey":
    cmdGetHotkey()
case "download-model":
    let size = args.count > 2 ? args[2] : "base.en"
    cmdDownloadModel(size)
case "benchmark":
    cmdBenchmark(
        engine: args.count > 2 ? args[2] : nil,
        model: args.count > 3 ? args[3] : nil
    )
case "long-form-benchmark":
    cmdLongFormBenchmark(
        engine: args.count > 2 ? args[2] : nil,
        model: args.count > 3 ? args[3] : nil
    )
case "real-speech-crucible":
    cmdRealSpeechCrucible(
        action: args.count > 2 ? args[2] : nil,
        sampleID: args.count > 3 ? args[3] : nil
    )
case "hotkey-diagnose":
    cmdHotkeyDiagnose()
case "contract-fixture":
    cmdContractFixture()
case "transcribe-file":
    cmdTranscribeFile(
        path: args.count > 2 ? args[2] : nil,
        formatName: args.count > 3 ? args[3] : nil
    )
case "status":
    cmdStatus()
case "--help", "-h", "help":
    printUsage()
case nil:
    printUsage()
default:
    print("Unknown command: \(command!)")
    printUsage()
    exit(1)
}
