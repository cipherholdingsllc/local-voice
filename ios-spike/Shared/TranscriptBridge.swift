//
//  TranscriptBridge.swift
//  Local Voice
//
//  Copyright (c) 2026 Cipher Holdings LLC
//  SPDX-License-Identifier: MIT
//

import Foundation

/// Transcript-only bridge between the container app and keyboard extension.
/// Keyboard extensions cannot access the microphone and cannot reliably wake a
/// suspended container app to begin recording.
public enum TranscriptBridge {
    public static let appGroupID = "group.com.cipherholdings.localvoice"
    public static let darwinNotificationName = "com.cipherholdings.localvoice.transcript" as CFString

    public enum RecordingSignal: String, Codable, Sendable {
        case idle
        case startRequested
        case recording
        case stopRequested
        case transcribing
        case ready
        case failed
    }

    public struct TranscriptPayload: Codable, Sendable, Equatable {
        public var text: String
        public var sessionID: UUID
        public var createdAt: Date
        public var isFinal: Bool

        public init(text: String, sessionID: UUID, createdAt: Date = Date(), isFinal: Bool = true) {
            self.text = text
            self.sessionID = sessionID
            self.createdAt = createdAt
            self.isFinal = isFinal
        }
    }

    private enum Keys {
        static let recordingSignal = "localvoice.recordingSignal"
        static let activeSessionID = "localvoice.activeSessionID"
        static let lastTranscriptFile = "last_transcript.json"
    }

    // MARK: - Storage

    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var transcriptFileURL: URL? {
        containerURL?.appendingPathComponent(Keys.lastTranscriptFile)
    }

    // MARK: - Signal (UserDefaults + Darwin notify)

    @discardableResult
    public static func postSignal(_ signal: RecordingSignal, sessionID: UUID? = nil) -> UUID {
        let defaults = sharedDefaults
        let sid = sessionID ?? UUID()
        defaults?.set(signal.rawValue, forKey: Keys.recordingSignal)
        defaults?.set(sid.uuidString, forKey: Keys.activeSessionID)
        defaults?.synchronize()
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotificationName),
            nil,
            nil,
            true
        )
        return sid
    }

    public static func currentSignal() -> RecordingSignal {
        guard
            let raw = sharedDefaults?.string(forKey: Keys.recordingSignal),
            let signal = RecordingSignal(rawValue: raw)
        else {
            return .idle
        }
        return signal
    }

    public static func activeSessionID() -> UUID? {
        guard let raw = sharedDefaults?.string(forKey: Keys.activeSessionID) else { return nil }
        return UUID(uuidString: raw)
    }

    public static func observeSignals(handler: @escaping () -> Void) -> DarwinObserver {
        DarwinObserver(name: darwinNotificationName, handler: handler)
    }

    // MARK: - Transcript file bridge

    public static func writeTranscript(_ payload: TranscriptPayload) throws {
        guard let url = transcriptFileURL else {
            throw BridgeError.appGroupUnavailable
        }
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: [.atomic])
        postSignal(.ready, sessionID: payload.sessionID)
    }

    public static func readTranscript() throws -> TranscriptPayload? {
        guard let url = transcriptFileURL, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TranscriptPayload.self, from: data)
    }

    public static func clearTranscript() {
        guard let url = transcriptFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public static func resetSession() {
        clearTranscript()
        postSignal(.idle)
    }

    public enum BridgeError: Error, LocalizedError {
        case appGroupUnavailable

        public var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                return "App Group container unavailable. Enable \(appGroupID) on both targets."
            }
        }
    }
}

/// Lightweight Darwin notification observer for extension ↔ app wakeups.
public final class DarwinObserver {
    private let token: UnsafeMutableRawPointer

    public init(name: CFString, handler: @escaping () -> Void) {
        let box = ObserverBox(handler: handler)
        token = Unmanaged.passRetained(box).toOpaque()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            token,
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<ObserverBox>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            name,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            token
        )
        Unmanaged<ObserverBox>.fromOpaque(token).release()
    }

    private final class ObserverBox {
        let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
    }
}
