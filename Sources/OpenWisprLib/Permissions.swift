import AppKit
import AVFoundation
import ApplicationServices
import Foundation

public struct LocalVoicePermissionSnapshot: Equatable, Sendable {
    public let microphone: Bool
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public let postEvent: Bool

    public init(
        microphone: Bool,
        accessibility: Bool,
        inputMonitoring: Bool,
        postEvent: Bool = false
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.postEvent = postEvent
    }

    public var hotkeyReady: Bool {
        inputMonitoring
    }

    /// Full AX *or* PostEvent is enough to attempt insert. PostEvent is the
    /// CGEvent paste grant; AX is the selected-text write grant.
    public var canInsert: Bool {
        accessibility || postEvent
    }

    public var dictationReady: Bool {
        // Mic + shortcut are enough to dictate. Insert permission is
        // attempted anyway; do not park the app in "permission required"
        // and skip typing while we are testing.
        microphone && inputMonitoring
    }

    public var blockingSummary: String? {
        if !inputMonitoring {
            return "Input Monitoring is required for the recording shortcut"
        }
        if !microphone {
            return "Microphone access is required to dictate"
        }
        return nil
    }

    public func runtimeReady(hotkeyMonitorReady: Bool) -> Bool {
        dictationReady && hotkeyMonitorReady
    }
}

public struct Permissions {
    public static func snapshot() -> LocalVoicePermissionSnapshot {
        LocalVoicePermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: InputMonitoringAccess.isGranted(),
            postEvent: PostEventAccess.isGranted()
        )
    }

    static func ensureMicrophone(completion: ((Bool) -> Void)? = nil) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("Microphone: granted")
            completion?(true)
        case .notDetermined:
            print("Microphone: requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("Microphone: \(granted ? "granted" : "denied")")
                DispatchQueue.main.async {
                    completion?(granted)
                }
            }
        default:
            print("Microphone: denied — grant in System Settings → Privacy & Security → Microphone")
            completion?(false)
        }
    }

    static func openSettings(for capability: LocalVoicePermissionCapability) {
        switch capability {
        case .inputMonitoring:
            openInputMonitoringSettings()
        case .microphone:
            openMicrophoneSettings()
        case .accessibility:
            openAccessibilitySettings()
        }
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Same Settings pane as Accessibility; this is the API that actually
        // authorizes CGEvent paste on macOS 26.
        _ = PostEventAccess.request()
    }

    static func openAccessibilitySettings() {
        promptAccessibility()
        PrivacySettingsURL.open(.accessibility)
    }

    static func openInputMonitoringSettings() {
        InputMonitoringAccess.registerWithTCC()
        PrivacySettingsURL.open(.inputMonitoring)
    }

    static func openMicrophoneSettings() {
        PrivacySettingsURL.open(.microphone)
    }

    @discardableResult
    static func requestInputMonitoring(openSettings: Bool = true) -> Bool {
        if InputMonitoringAccess.isGranted() {
            print("Input Monitoring: granted")
            return true
        }
        print("Input Monitoring: requesting...")
        if openSettings {
            InputMonitoringAccess.registerWithTCC()
            PrivacySettingsURL.open(.inputMonitoring)
        } else {
            InputMonitoringAccess.registerWithTCCAsync()
        }
        let granted = InputMonitoringAccess.isGranted()
        if !granted {
            print("Input Monitoring: denied — grant in System Settings → Privacy & Security → Input Monitoring")
        }
        return granted
    }
}
