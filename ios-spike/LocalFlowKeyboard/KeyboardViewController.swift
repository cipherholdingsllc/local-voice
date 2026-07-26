//
//  KeyboardViewController.swift
//  LocalFlowKeyboard
//
//  Copyright (c) 2026 Cipher Holdings LLC
//  SPDX-License-Identifier: MIT
//

import UIKit

/// UI-only keyboard extension. Cannot access the microphone (iOS hard constraint).
/// Flow: globe → mic → speak → checkmark. Recording runs in the container app via App Group signals.
final class KeyboardViewController: UIInputViewController {
    private enum FlowStep {
        case globe
        case mic
        case speaking
        case checkmark
    }

    private var step: FlowStep = .globe {
        didSet { refreshChrome() }
    }

    private var activeSessionID: UUID?
    private var pollTimer: Timer?
    private var signalObserver: DarwinObserver?

    private let toolbar = UIStackView()
    private let flowButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let hintLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureChrome()
        wireDarwinObserver()
        resetFlow()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPolling()
    }

    deinit {
        signalObserver = nil
        stopPolling()
    }

    // MARK: - UI

    private func configureChrome() {
        view.backgroundColor = UIColor.systemGray6

        toolbar.axis = .horizontal
        toolbar.alignment = .center
        toolbar.distribution = .fill
        toolbar.spacing = 12
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        flowButton.titleLabel?.font = .systemFont(ofSize: 28)
        flowButton.addTarget(self, action: #selector(flowButtonTapped), for: .touchUpInside)
        flowButton.accessibilityTraits = .button
        toolbar.addArrangedSubview(flowButton)

        let globeSwitch = UIButton(type: .system)
        globeSwitch.setImage(UIImage(systemName: "globe"), for: .normal)
        globeSwitch.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globeSwitch.accessibilityLabel = "Switch keyboard"
        toolbar.addArrangedSubview(globeSwitch)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 4),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            hintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            hintLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8)
        ])
    }

    private func refreshChrome() {
        switch step {
        case .globe:
            flowButton.setImage(UIImage(systemName: "globe.americas.fill"), for: .normal)
            flowButton.accessibilityLabel = "Start dictation flow"
            statusLabel.text = "LocalFlow"
            hintLabel.text = "Tap to arm mic (container app records audio)."
        case .mic:
            flowButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
            flowButton.accessibilityLabel = "Start recording in container app"
            statusLabel.text = "Ready"
            hintLabel.text = "Open LocalFlow app in background, then tap mic."
        case .speaking:
            flowButton.setImage(UIImage(systemName: "waveform"), for: .normal)
            flowButton.accessibilityLabel = "Speaking"
            statusLabel.text = "Listening…"
            hintLabel.text = "Speak now. Tap checkmark when finished."
        case .checkmark:
            flowButton.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
            flowButton.accessibilityLabel = "Insert transcript"
            statusLabel.text = "Transcript ready"
            hintLabel.text = "Tap to insert text at cursor."
        }
    }

    // MARK: - Flow actions

    @objc private func flowButtonTapped() {
        switch step {
        case .globe:
            step = .mic
        case .mic:
            beginRecordingRequest()
        case .speaking:
            finishRecordingRequest()
        case .checkmark:
            insertTranscriptIfReady()
        }
    }

    private func resetFlow() {
        step = .globe
        activeSessionID = nil
        stopPolling()
    }

    private func beginRecordingRequest() {
        TranscriptBridge.clearTranscript()
        let sessionID = TranscriptBridge.postSignal(.startRequested)
        activeSessionID = sessionID
        step = .speaking
        startPolling(for: sessionID)
    }

    private func finishRecordingRequest() {
        guard let sessionID = activeSessionID else { return }
        TranscriptBridge.postSignal(.stopRequested, sessionID: sessionID)
        statusLabel.text = "Transcribing…"
        hintLabel.text = "Local WhisperKit stub running in container app."
        startPolling(for: sessionID)
    }

    private func insertTranscriptIfReady() {
        guard
            let payload = try? TranscriptBridge.readTranscript(),
            payload.isFinal,
            !payload.text.isEmpty
        else {
            statusLabel.text = "No transcript yet"
            return
        }

        textDocumentProxy.insertText(payload.text)
        TranscriptBridge.resetSession()
        resetFlow()
    }

    // MARK: - Polling + Darwin

    private func wireDarwinObserver() {
        signalObserver = TranscriptBridge.observeSignals { [weak self] in
            DispatchQueue.main.async {
                self?.handleBridgeSignal()
            }
        }
    }

    private func handleBridgeSignal() {
        guard let sessionID = activeSessionID else { return }
        let signal = TranscriptBridge.currentSignal()

        switch signal {
        case .recording:
            statusLabel.text = "Recording…"
        case .transcribing:
            statusLabel.text = "Transcribing…"
        case .ready:
            if let payload = try? TranscriptBridge.readTranscript(), payload.sessionID == sessionID {
                step = .checkmark
                statusLabel.text = "“\(payload.text.prefix(42))…”"
            }
        case .failed:
            statusLabel.text = "Dictation failed"
            hintLabel.text = "Check LocalFlow container app logs."
            stopPolling()
        default:
            break
        }
    }

    private func startPolling(for sessionID: UUID) {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollTranscript(sessionID: sessionID)
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollTranscript(sessionID: UUID) {
        let signal = TranscriptBridge.currentSignal()
        if signal == .ready {
            if let payload = try? TranscriptBridge.readTranscript(), payload.sessionID == sessionID, payload.isFinal {
                step = .checkmark
                statusLabel.text = "Transcript ready"
                stopPolling()
            }
        } else if signal == .failed {
            statusLabel.text = "Dictation failed"
            stopPolling()
        }
    }
}
