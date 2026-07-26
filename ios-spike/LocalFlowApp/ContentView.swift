//
//  ContentView.swift
//  Local Voice
//
//  Copyright (c) 2026 Cipher Holdings LLC
//  SPDX-License-Identifier: MIT
//

import AVFoundation
import Speech
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var coordinator = DictationCoordinator()

    private let graphite = Color(red: 0.035, green: 0.055, blue: 0.051)
    private let panel = Color(red: 0.075, green: 0.102, blue: 0.094)
    private let mint = Color(red: 0.36, green: 0.94, blue: 0.72)

    var body: some View {
        ZStack {
            graphite.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    captureCard

                    if !coordinator.transcript.isEmpty {
                        transcriptCard
                    }

                    privacyCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
        .preferredColorScheme(.dark)
        .task { await coordinator.bootstrap() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(mint)
                    .frame(width: 42, height: 42)
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(graphite)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Local Voice")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Private dictation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("On device", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(mint)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(mint.opacity(0.10), in: Capsule())
        }
    }

    private var captureCard: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(coordinator.phase.eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(mint)
                    Text(coordinator.phase.title)
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                Circle()
                    .fill(coordinator.phase.indicatorColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: coordinator.phase.indicatorColor.opacity(0.65), radius: 6)
            }

            waveform

            Button {
                Task { await coordinator.toggleCapture() }
            } label: {
                ZStack {
                    Circle()
                        .fill(coordinator.isRecording ? Color.red.opacity(0.15) : mint.opacity(0.12))
                        .frame(width: 104, height: 104)
                    Circle()
                        .fill(coordinator.isRecording ? Color.red : mint)
                        .frame(width: 76, height: 76)
                    Image(systemName: coordinator.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(graphite)
                }
            }
            .buttonStyle(.plain)
            .disabled(!coordinator.phase.canRecord)
            .accessibilityLabel(coordinator.isRecording ? "Stop recording" : "Start recording")

            Text(coordinator.isRecording ? "Tap to finish" : "Tap to dictate")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if !coordinator.partialTranscript.isEmpty && coordinator.isRecording {
                Text(coordinator.partialTranscript)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            if let detail = coordinator.phase.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(coordinator.phase.isFailure ? .red : .secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<19, id: \.self) { index in
                Capsule()
                    .fill(coordinator.isRecording ? mint : Color.white.opacity(0.18))
                    .frame(width: 3, height: waveformHeight(at: index))
            }
        }
        .frame(height: 42)
        .animation(.easeInOut(duration: 0.28), value: coordinator.partialTranscript.count)
    }

    private func waveformHeight(at index: Int) -> CGFloat {
        guard coordinator.isRecording else {
            return CGFloat(8 + (index % 5) * 3)
        }
        let seed = coordinator.partialTranscript.count + index * 7
        return CGFloat(12 + (seed % 28))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Latest transcript", systemImage: "text.quote")
                    .font(.headline)
                Spacer()

                Button {
                    coordinator.copyTranscript()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                ShareLink(item: coordinator.transcript) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Share transcript")
            }

            Text(coordinator.transcript)
                .font(.body)
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(.white.opacity(0.08))

            Label("Available in the Local Voice keyboard", systemImage: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(mint)

            VStack(alignment: .leading, spacing: 5) {
                Text("Local by design")
                    .font(.subheadline.weight(.semibold))
                Text("Audio is processed with Apple's on-device speech recognizer. Local Voice does not upload or retain raw audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(17)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
    }
}

// MARK: - State

@MainActor
final class DictationCoordinator: ObservableObject {
    enum Phase: Equatable {
        case preparing
        case ready
        case listening
        case finishing
        case unavailable(String)
        case failed(String)

        var eyebrow: String {
            switch self {
            case .preparing: return "Preparing"
            case .ready: return "Ready"
            case .listening: return "Listening"
            case .finishing: return "Finishing"
            case .unavailable: return "Unavailable"
            case .failed: return "Needs attention"
            }
        }

        var title: String {
            switch self {
            case .preparing: return "Checking your device"
            case .ready: return "Ready when you are"
            case .listening: return "Speak naturally"
            case .finishing: return "Polishing transcript"
            case .unavailable: return "On-device speech unavailable"
            case .failed: return "Dictation paused"
            }
        }

        var detail: String? {
            switch self {
            case .preparing: return "Microphone and speech permissions are required."
            case .unavailable(let message), .failed(let message): return message
            default: return nil
            }
        }

        var indicatorColor: Color {
            switch self {
            case .ready: return Color(red: 0.36, green: 0.94, blue: 0.72)
            case .listening: return .red
            case .finishing, .preparing: return .orange
            case .unavailable, .failed: return .red
            }
        }

        var canRecord: Bool {
            switch self {
            case .ready, .listening: return true
            default: return false
            }
        }

        var isFailure: Bool {
            switch self {
            case .unavailable, .failed: return true
            default: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .preparing
    @Published private(set) var partialTranscript = ""
    @Published private(set) var transcript = ""

    var isRecording: Bool { phase == .listening }

    private let speechEngine = OnDeviceSpeechEngine()

    func bootstrap() async {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            transcript = "The fastest voice tool is the one that disappears into your workflow."
            phase = .ready
            return
        }
#endif

        if let saved = try? TranscriptBridge.readTranscript() {
            transcript = saved.text
        }

        let microphoneGranted = await Self.requestMicrophonePermission()
        let speechGranted = await Self.requestSpeechPermission()

        guard microphoneGranted, speechGranted else {
            phase = .unavailable("Enable Microphone and Speech Recognition in Settings to dictate.")
            return
        }

        guard speechEngine.supportsOnDeviceRecognition else {
            phase = .unavailable("This device or language does not currently support Apple's on-device speech recognition.")
            return
        }

        phase = .ready
    }

    func toggleCapture() async {
        if isRecording {
            await finishCapture()
        } else {
            startCapture()
        }
    }

    func copyTranscript() {
        UIPasteboard.general.string = transcript
    }

    private func startCapture() {
        do {
            partialTranscript = ""
            try speechEngine.start(
                onPartial: { [weak self] text in
                    self?.partialTranscript = text
                },
                onFailure: { [weak self] message in
                    self?.phase = .failed(message)
                }
            )
            phase = .listening
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func finishCapture() async {
        phase = .finishing
        let result = await speechEngine.stop()
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        partialTranscript = ""

        guard !cleaned.isEmpty else {
            phase = .failed("No speech was detected. Try again and keep the microphone unobstructed.")
            return
        }

        transcript = cleaned
        let payload = TranscriptBridge.TranscriptPayload(
            text: cleaned,
            sessionID: UUID(),
            isFinal: true
        )
        try? TranscriptBridge.writeTranscript(payload)
        phase = .ready
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

// MARK: - On-device speech

@MainActor
final class OnDeviceSpeechEngine {
    enum EngineError: LocalizedError {
        case unavailable
        case invalidAudioFormat

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "On-device speech recognition is unavailable for the current language."
            case .invalidAudioFormat:
                return "The microphone did not provide a usable audio format."
            }
        }
    }

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestText = ""
    private var finishContinuation: CheckedContinuation<String, Never>?
    private var finishTimeout: Task<Void, Never>?

    var supportsOnDeviceRecognition: Bool {
        recognizer?.supportsOnDeviceRecognition == true
    }

    func start(
        onPartial: @escaping (String) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            throw EngineError.unavailable
        }

        cancel()
        latestText = ""

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw EngineError.invalidAudioFormat
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        self.request = request

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.latestText = result.bestTranscription.formattedString
                    onPartial(self.latestText)
                    if result.isFinal {
                        self.completeStop()
                    }
                }
                if let error {
                    if self.finishContinuation == nil {
                        onFailure(error.localizedDescription)
                    }
                    self.completeStop()
                }
            }
        }
    }

    func stop() async -> String {
        guard audioEngine.isRunning else { return latestText }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()

        return await withCheckedContinuation { continuation in
            finishContinuation = continuation
            finishTimeout?.cancel()
            finishTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 900_000_000)
                self?.completeStop()
            }
        }
    }

    private func completeStop() {
        finishTimeout?.cancel()
        finishTimeout = nil
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        finishContinuation?.resume(returning: latestText)
        finishContinuation = nil
    }

    private func cancel() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        completeStop()
    }
}

#Preview {
    ContentView()
}
