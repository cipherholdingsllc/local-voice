//
//  KeyboardViewController.swift
//  Local Voice Keyboard
//
//  Copyright (c) 2026 Cipher Holdings LLC
//  SPDX-License-Identifier: MIT
//

import UIKit

/// A truthful keyboard extension: iOS does not grant keyboard extensions
/// microphone access, so this surface inserts transcripts completed in the app.
final class KeyboardViewController: UIInputViewController {
    private let graphite = UIColor(red: 0.035, green: 0.055, blue: 0.051, alpha: 1)
    private let panel = UIColor(red: 0.075, green: 0.102, blue: 0.094, alpha: 1)
    private let mint = UIColor(red: 0.36, green: 0.94, blue: 0.72, alpha: 1)

    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)
    private var signalObserver: DarwinObserver?
    private var latestPayload: TranscriptBridge.TranscriptPayload?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureChrome()
        signalObserver = TranscriptBridge.observeSignals { [weak self] in
            DispatchQueue.main.async {
                self?.reloadTranscript()
            }
        }
        reloadTranscript()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadTranscript()
    }

    private func configureChrome() {
        view.backgroundColor = graphite

        let brandIcon = UIImageView(image: UIImage(systemName: "waveform"))
        brandIcon.tintColor = mint
        brandIcon.contentMode = .scaleAspectFit
        brandIcon.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "LOCAL VOICE"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = .secondaryLabel
        globeButton.accessibilityLabel = "Switch keyboard"
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globeButton.translatesAutoresizingMaskIntoConstraints = false

        let header = UIStackView(arrangedSubviews: [brandIcon, titleLabel, UIView(), globeButton])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        previewLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        previewLabel.font = .preferredFont(forTextStyle: .body)
        previewLabel.numberOfLines = 3
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        insertButton.backgroundColor = mint
        insertButton.tintColor = graphite
        insertButton.layer.cornerRadius = 13
        insertButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        insertButton.addTarget(self, action: #selector(insertLatestTranscript), for: .touchUpInside)
        insertButton.translatesAutoresizingMaskIntoConstraints = false

        let card = UIView()
        card.backgroundColor = panel
        card.layer.cornerRadius = 18
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(previewLabel)

        view.addSubview(header)
        view.addSubview(card)
        view.addSubview(insertButton)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),

            brandIcon.widthAnchor.constraint(equalToConstant: 20),
            brandIcon.heightAnchor.constraint(equalToConstant: 20),
            globeButton.widthAnchor.constraint(equalToConstant: 40),
            globeButton.heightAnchor.constraint(equalToConstant: 36),

            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 78),

            previewLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            previewLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            previewLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            previewLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),

            insertButton.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 10),
            insertButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            insertButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            insertButton.heightAnchor.constraint(equalToConstant: 48),
            insertButton.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -10)
        ])
    }

    private func reloadTranscript() {
        latestPayload = try? TranscriptBridge.readTranscript()
        let text = latestPayload?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasTranscript = !text.isEmpty

        previewLabel.text = hasTranscript
            ? text
            : "Record in the Local Voice app, then return here to insert the finished transcript."

        insertButton.isEnabled = hasTranscript
        insertButton.alpha = hasTranscript ? 1 : 0.45
        insertButton.setTitle(
            hasTranscript ? "Insert latest transcript" : "No transcript ready",
            for: .normal
        )
        insertButton.setImage(
            UIImage(systemName: hasTranscript ? "arrow.down.doc.fill" : "mic.slash.fill"),
            for: .normal
        )
        insertButton.configuration?.imagePadding = 8
    }

    @objc private func insertLatestTranscript() {
        guard let text = latestPayload?.text, !text.isEmpty else {
            reloadTranscript()
            return
        }
        textDocumentProxy.insertText(text)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
