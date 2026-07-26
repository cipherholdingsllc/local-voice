//
//  ContentView.swift
//  LocalFlow
//
//  Copyright (c) 2026 Cipher Holdings LLC
//  SPDX-License-Identifier: MIT
//

import AVFoundation
import SwiftUI

/// Container app owns microphone access, recording, and on-device STT.
/// The keyboard extension triggers work via App Group signals and polls for transcripts.
struct ContentView: View {
    @StateObject private var coordinator = DictationCoordinator()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Container app · mic owner", systemImage: "mic.circle.fill")
                    .font(.headline)

                statusCard

                if !coordinator.lastTranscript.isEmpty {
                    GroupBox("Last transcript") {
                        Text(coordinator.lastTranscript)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("Keep this app running in the background while using the LocalFlow keyboard. iOS keyboard extensions cannot access the microphone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("LocalFlow")
            .task { await coordinator.bootstrap() }
        }
    }

    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(coordinator.statusColor)
                        .frame(width: 10, height: 10)
                    Text(coordinator.statusText)
                        .font(.subheadline.weight(.medium))
                }
                if coordinator.isRecording {
                    Text("Recording from keyboard request…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Coordinator

@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var statusText = "Idle"
    @Published private(set) var isRecording = false
    @Published private(set) var lastTranscript = ""

    var statusColor: Color {
        switch TranscriptBridge.currentSignal() {
        case .recording, .startRequested: return .red
        case .transcribing: return .orange
        case .ready: return .green
        case .failed: return .pink
        default: return .gray
        }
    }

    private let recorder = AudioCaptureEngine()
    private let transcriber = WhisperKitTranscriberStub()
    private var signalObserver: DarwinObserver?
    private var activeSessionID: UUID?

    func bootstrap() async {
        await requestMicrophoneAccess()
        wireBridgeObserver()
        statusText = "Waiting for keyboard"
    }

    private func requestMicrophoneAccess() async {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { _ in
                continuation.resume()
            }
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }

    private func wireBridgeObserver() {
        signalObserver = TranscriptBridge.observeSignals { [weak self] in
            Task { @MainActor in
                await self?.handleBridgeSignal()
            }
        }
    }

    private func handleBridgeSignal() async {
        let signal = TranscriptBridge.currentSignal()
        switch signal {
        case .startRequested:
            guard !isRecording else { return }
            activeSessionID = TranscriptBridge.activeSessionID()
            await startRecording()
        case .stopRequested:
            guard isRecording else { return }
            await stopAndTranscribe()
        default:
            break
        }
    }

    private func startRecording() async {
        guard let sessionID = activeSessionID else { return }
        do {
            try recorder.start()
            isRecording = true
            statusText = "Recording"
            TranscriptBridge.postSignal(.recording, sessionID: sessionID)
        } catch {
            isRecording = false
            statusText = "Mic error"
            TranscriptBridge.postSignal(.failed, sessionID: sessionID)
        }
    }

    private func stopAndTranscribe() async {
        guard let sessionID = activeSessionID else { return }
        isRecording = false
        statusText = "Transcribing"
        TranscriptBridge.postSignal(.transcribing, sessionID: sessionID)

        let samples = recorder.stop()
        let text = await transcriber.transcribe(samples: samples)

        lastTranscript = text
        statusText = "Ready"

        let payload = TranscriptBridge.TranscriptPayload(
            text: text,
            sessionID: sessionID,
            isFinal: true
        )
        try? TranscriptBridge.writeTranscript(payload)
    }
}

// MARK: - AVAudioEngine capture

final class AudioCaptureEngine {
    private let engine = AVAudioEngine()
    private var bufferSamples: [Float] = []

    func start() throws {
        bufferSamples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            self?.bufferSamples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return bufferSamples
    }
}

// MARK: - WhisperKit STT stub (replace with WhisperKit SPM in production)

struct WhisperKitTranscriberStub {
    func transcribe(samples: [Float]) async -> String {
        // Simulate on-device inference latency for spike validation.
        try? await Task.sleep(nanoseconds: 350_000_000)
        let seconds = Double(samples.count) / 16_000.0
        if samples.isEmpty {
            return ""
        }
        return "[LocalFlow stub] \(String(format: "%.1f", seconds))s captured on-device."
    }
}

#Preview {
    ContentView()
}
